---
name: custom-review
description: Multi-agent PR review — fans out 4 parallel subagents (bug+in-change-invariant scan on Opus, blast-radius+caller-invariants on Opus, CLAUDE.md/AGENTS.md conventions on Sonnet, git history on Sonnet), runs a single Sonnet triage that dedupes findings, assigns each both a bucket (Issue / Likely intentional / Pre-existing / Outside change) and a severity (🔴 high / 🟡 medium / 🔵 nit / ❓ question) anchored to mergeability or reviewer-uncertainty, and posts a hybrid GitHub PR review (inline comments for in-diff findings, body comment for out-of-diff findings). Use when the user says "custom review", "deep review", "multi-agent review", "/custom-review", or hands you a PR URL/number with "review this carefully". NOT for local pre-commit (use /review-simplify) and NOT for post-PR-open bot-driven loops (use /pr-review-and-fix).
---

# custom-review

Independent multi-agent review of an open GitHub PR. Posts a single GitHub review with inline comments for in-diff findings and a body comment for out-of-diff context findings. Runs once and exits — it is **not** a loop and does **not** apply fixes (that's `/pr-review-and-fix`).

## Assumptions

- Working directory is a git clone of the PR's repo. `gh repo view` must resolve.
- `gh` CLI is authenticated as a user who can comment on the PR.
- The PR is **open** (not closed, not draft). The skill skips otherwise.
- Build/typecheck/lint signals are handled separately by CI — this skill does not run them and does not flag findings a linter/typechecker would catch.

## Pipeline overview

```
arg → eligibility → conventions gather → PR summary
                                              ↓
                              4 parallel review agents
                                              ↓
                                       Sonnet triage
                                              ↓
                              re-check eligibility → post review
```

## Step 1 — Locate the PR

Argument forms accepted (in order):

1. PR URL: `https://github.com/<owner>/<repo>/pull/<N>` — parse owner/repo/N from URL.
2. PR number: `<N>` — resolve owner/repo from current `gh repo view`.
3. No argument: auto-detect from current branch via `gh pr view --json number,url,headRepositoryOwner,headRepository,headRefOid,baseRefName,state,isDraft,reviews,comments,title,body`.

If no PR exists for the current branch and no arg was given, exit with: "No PR found for current branch. Open a PR first (`gh pr create`) or pass a PR number/URL."

Store in shell vars: `PR_NUM`, `PR_URL`, `OWNER`, `REPO`, `HEAD_SHA` (full SHA, used for the marker and for the review API `commit_id`).

## Step 2 — Eligibility check (bash, no model)

Skip the review and exit silently if any of the following:

1. **State / draft:**
   ```bash
   gh pr view "$PR_NUM" --json state,isDraft -q '"\(.state) \(.isDraft)"'
   ```
   Skip if `state != "OPEN"` or `isDraft == true`.

2. **Already reviewed at this SHA.** Look for a hidden marker in any existing review body or comment body on the PR:
   ```
   <!-- custom-review:<SHA> -->
   ```
   Fetch with:
   ```bash
   gh api "repos/$OWNER/$REPO/pulls/$PR_NUM/reviews" -q '.[].body'
   gh api "repos/$OWNER/$REPO/issues/$PR_NUM/comments" -q '.[].body'
   ```
   If any marker is found with `SHA == HEAD_SHA`, skip. If markers exist with different SHAs, the PR has new commits — proceed and post a fresh review.

If skipping, print the reason ("PR is draft" / "Already reviewed at SHA abc1234") and exit. Do not post anything.

## Step 3 — Gather conventions (bash, no model)

Find all `CLAUDE.md` and `AGENTS.md` files relevant to the PR:

```bash
# repo root convention files
ROOT_FILES=$(ls CLAUDE.md AGENTS.md 2>/dev/null)

# convention files inside any modified directory
MODIFIED_DIRS=$(gh pr diff "$PR_NUM" --name-only | xargs -I{} dirname {} | sort -u)
DIR_FILES=$(echo "$MODIFIED_DIRS" | while read -r d; do
  ls "$d"/CLAUDE.md "$d"/AGENTS.md 2>/dev/null
done | sort -u)

CONVENTION_PATHS=$(printf '%s\n%s\n' "$ROOT_FILES" "$DIR_FILES" | sort -u | grep -v '^$')
```

Pass the resulting path list to agent #3. **Do not pre-load `.claude/docs/*.md`** — agent #3 decides per-PR whether to fetch domain docs based on the convention files' "Working on X → load Y.md" tables.

If no convention files exist anywhere, agent #3 is still launched but will produce zero findings (don't fabricate rules).

## Step 4 — PR summary (1× Sonnet subagent)

Spawn one general-purpose Sonnet subagent with this prompt (paraphrased — adapt for clarity):

> Summarize what PR #<N> in <owner>/<repo> is trying to do. Read the PR title, body, and `gh pr diff $PR_NUM`. Return 3–5 sentences covering: (1) the intent, (2) the main code locations changed, (3) any notable architectural choices visible in the diff (e.g. new endpoints, schema changes, removed code paths). Keep it neutral and factual — not a review.

Save the summary; it is passed as context to all 4 review agents AND to the triage step. Cheap shared context vs each agent re-deriving intent from scratch.

## Step 5 — Four parallel review agents

Spawn **all four in a single message** (parallel tool calls). Each gets: the PR URL, PR number, HEAD_SHA, the PR summary from step 4, and the convention file paths from step 3.

**Launch order within the message: Opus agents first (#1 bug, #2 blast), then Sonnet agents (#3 conventions, #4 history).** Even with parallel tool calls, list the slow agents first so they queue ahead — Opus latency dominates wall-clock time; you don't want a Sonnet ahead of an Opus in the dispatch list.

Each agent returns a JSON-ish list of findings (one finding per item) in the shape:

```
- file: <path>
  line: <line number or range>
  description: <2–4 sentences, what's wrong and why>
  evidence: <quoted code OR CLAUDE.md/AGENTS.md citation OR git blame line>
  agent: <"#1 bug+invariant" | "#2 blast" | "#3 conventions" | "#4 history">
```

### Agent #1 — Bug scan + in-change invariants (Opus, general-purpose)

**Prompt skeleton:**

> Scan PR #<N> for obvious bugs and in-change invariant violations. PR summary: <step 4 output>. Read the diff via `gh pr diff $PR_NUM`.
>
> Two responsibilities:
>
> **A. Obvious bugs in the diff.** Shallow read — focus on the changes themselves, don't go reading the whole codebase. Look for: null/undefined misuse, off-by-one, async/await mistakes, error-swallowing, race conditions, resource leaks, security issues (SQLi, XSS, auth bypass), incorrect API usage.
>
> **B. In-change invariant violations.** Did the change break an invariant evident from the code being changed? Categories:
> - **Function contract:** return type narrowed/widened (e.g. `Promise<X>` → `Promise<X | null>`), parameter signature change, throw semantics changed.
> - **Type narrowing:** an `if (x)` branch that was previously safe is no longer safe after the change.
> - **Ordering/state machine:** a sequence of operations that must happen in a specific order is reordered or skipped.
> - **Lock/resource pairs:** lock acquired without release, file opened without close, connection without disposal.
> - **Caching/versioning:** cache key, schema version, or migration number not bumped despite schema/structural change.
>
> **Tool preference for type checks:** if a TypeScript LSP MCP is available (`mcp__typescript-lsp__*` or similar), use `hover` on changed symbols to confirm signature changes concretely. Otherwise read types from the code. Do **NOT** use LSP `diagnostics` — CI catches type errors; that's not a finding for this review.
>
> Skip only these (the surface floor):
> - **Pure pedantry** a senior engineer wouldn't even mention (e.g. "rename this variable", "consider extracting a helper", optional refactors with no measurable benefit).
> - **CI-catchable issues** (missing imports, type errors, formatting, lint).
> - **Misread of the diff** — if you're unsure the cited line actually says what you think, drop the finding.
>
> **Do NOT pre-filter** for "this is lint-ignored" / "this is widespread already" / "this is just a nit" / "this is in a test file" / "this is on a line outside the diff". Surface those — the triage step grades severity (🔴/🟡/🔵/❓) and applies downgrade heuristics for lint-ignored, widespread-precedent, test code, and out-of-diff findings. If you're genuinely unsure whether a finding is a bug or intentional, surface it with hedging language ("not sure if intentional", "could be a bug or could be the design") — triage will grade those as ❓ question. Agents over-filtering means triage can't grade.
>
> Return findings in the shape above.

### Agent #2 — Blast radius + caller-side invariants (Opus, general-purpose)

**Prompt skeleton:**

> For PR #<N>, check the impact on surrounding code: callers, importers, adjacent same-file code. PR summary: <step 4 output>.
>
> For each modified symbol (function, class, exported const, type):
>
> **A. Callers.** Who calls it? Do their assumptions still hold after the change?
> **B. Importers.** Which files `import` from the modified module? If exported types/signatures changed, do they still compile / behave correctly?
> **C. Adjacent same-file code.** Are there sibling functions in the same file that share assumptions with the modified code? Common pattern: "you updated the validator but the parallel `validateLegacy` two functions down has the same bug — did you mean to update it too?"
> **D. Caller-side invariants.** Does the change violate an assumption a caller makes that the type system doesn't enforce? Examples:
>   - Function used to return non-null; now can return null; callers don't null-check.
>   - Function used to be synchronous; now async; callers don't await.
>   - Function used to throw on error; now returns sentinel value; callers don't check.
>   - Function used to be idempotent; now has side effects on repeated calls.
>
> **Tool preference order** (use the first available):
> 1. **TypeScript LSP** (`mcp__typescript-lsp__*`) — `findReferences` / `incomingCalls` for callers, `documentSymbols` for adjacent code, `hover` for type info. Best for TS — type-aware, no false positives.
> 2. **code-review-graph MCP** (`mcp__code-review-graph__*`) — `get_impact_radius_tool`, `get_affected_flows_tool`, `query_graph_tool` for cross-language structural traversal.
> 3. **grep + Read** — fallback. Grep for the symbol name; manually filter out obvious false matches.
>
> Do **not** chase deep transitive callees (callees-of-callees-of-callers). One hop out is enough.
>
> **Do not pre-filter** for nit-likeness — triage grades severity (🔴/🟡/🔵/❓) and caps out-of-diff findings at 🟡. Emit findings on lines outside the diff regardless — the triage step buckets them into Pre-existing or Outside change.
>
> Return findings in the shape above.

### Agent #3 — Conventions audit (Sonnet, general-purpose)

**Prompt skeleton:**

> Audit PR #<N> for compliance with project conventions. Convention files: <paths from step 3>. PR summary: <step 4 output>. Diff: read via `gh pr diff $PR_NUM`.
>
> Procedure:
> 1. Read all convention files. Follow any `@path` imports inside them.
> 2. Inspect each convention file for tables like "Working on X → load Y.md" or similar conditional-load instructions. If the PR's modified files match the X clause, fetch and read the linked Y.md domain doc. Do **not** load every domain doc indiscriminately.
> 3. For each finding, cite the specific rule (file + exact quote). No fabricated rules.
> 4. Skip rules that are guidance for *writing* code but not relevant during *review* (e.g. "write tests first" — CI signal, not a review concern).
> 5. **Do not pre-filter** for "this might be a nit" or "this is lint-ignored" or "this is widespread already". Surface those findings — the triage step grades severity (🔴/🟡/🔵/❓) and applies downgrade heuristics. Agents that over-filter rob triage of grading signal.
> 6. Surface findings on lines not modified by the PR — triage classifies them into the right bucket and severity.
>
> Return findings in the shape above. Empty list is fine.

### Agent #4 — Git history (Sonnet, general-purpose)

**Prompt skeleton:**

> Read the git history around PR #<N>'s changes for context-based issues. PR summary: <step 4 output>.
>
> Procedure:
> 1. For each modified file, run `git blame -L <hunk-start>,<hunk-end> -- <file>` on the surrounding hunks to see when those lines were last touched and by which commit.
> 2. For each suspicious change, run `git log --all --oneline -p -- <file> | head -200` and look for:
>    - Lines previously fixed in this exact way that this PR re-introduces.
>    - Lines added in a recent commit with a clear intent (e.g. "fix race condition") that this PR removes or weakens.
>    - Recurring bug patterns in this file's history that this PR fits the pattern of.
> 3. Only flag historical issues where the evidence is concrete — cite the commit SHA + commit message.
>
> Skip pure pedantry and "this file has been changed a lot" non-observations. **Do not pre-filter** for nit-likeness — surface real history-grounded findings, and triage will grade severity. Return findings in the shape above.

## Step 6 — Triage (1× Sonnet subagent)

After all 4 agents return, spawn one general-purpose Sonnet subagent for triage. Triage's job is **dedup + bucket + severity**, NOT scoring.

**Triage inputs:**
- All findings from the 4 agents (concatenated).
- PR summary from step 4.
- `gh pr diff $PR_NUM` (so triage can verify "is this line in the diff?").

**Triage prompt skeleton:**

> Triage these findings from 4 parallel code review agents into the final review.
>
> For each finding, do:
>
> 1. **Dedup.** If two agents flagged the same issue (same file + line + same root cause), keep only one — prefer the finding with stronger evidence (specific code/citation > vague description).
>
> 2. **Drop only these (the surface floor):**
>    - **Pure pedantry** a senior engineer wouldn't even mention (variable renames, optional helper extractions, pure stylistic preferences not backed by a convention file).
>    - **CI-catchable** (linter / typechecker / compiler).
>    - **Misread of diff** — the cited line doesn't actually say what the finding claims (verify before keeping).
>
>    **Do NOT drop for "lint-ignored", "test file", "widespread already", or "outside the diff".** Those become nits or downgraded medium — see severity heuristics below. The new triage rule is **grade, don't drop.**
>
> 3. **Classify each surviving finding into exactly one of 4 buckets**:
>
>    | Bucket | Rule | Posted as |
>    |---|---|---|
>    | `Issue` | Real, actionable problem on a line **the PR modified**. | Inline review comment on that line. |
>    | `Likely intentional` | The change in functionality looks suspicious in isolation but is consistent with the PR summary's stated intent — flag it for human verification, not as a bug. Line **is in the diff**. | Inline review comment on that line. |
>    | `Pre-existing` | Real issue, but the offending line was **not modified by this PR** AND git blame shows it predates the PR. | Body comment (out-of-diff). |
>    | `Outside change` | Real issue on a line **not modified by this PR** but adjacent to changes (caller, sibling, importer). Includes broken-caller-invariant findings. | Body comment (out-of-diff). |
>
>    To check "is this line in the diff?", look at the `gh pr diff` hunk ranges for the cited file. A line is "in the diff" if it appears with a `+` or `-` prefix in any hunk for that file. Lines in the surrounding context (no prefix) count as **not** in the diff.
>
> 4. **Assign severity** to each surviving finding. Severity is orthogonal to bucket.
>
>    **Anchor (the calibration test):** ask yourself, *"if this were the only finding on the PR, would I block merge?"*
>
>    | Sev | Mergeability test | Visual |
>    |---|---|---|
>    | `high` | Would block merge — correctness/security/data-integrity issue that will cause an incident or break user-facing behavior. | 🔴 emoji prefix |
>    | `medium` | Would ask the author to respond, but might still merge — meaningful change with non-trivial impact (subtle behavior widening, performance regression in hot path, test no longer exercises real code path, convention violation in production with real blast radius). | 🟡 emoji prefix |
>    | `nit` | Would merge without addressing — minor or already-silenced (style violations, log/comment quality, redundant-but-harmless code, optional improvements, naming). | 🔵 emoji prefix |
>    | `question` | Reviewer has genuine uncertainty whether this is an issue — depends on author intent not visible from code. Not asserting a problem, asking one. Triage assigns this when the originating agent hedged ("not sure if intentional", "could be a bug or could be the design") OR the finding genuinely requires author context to verify. Distinct from `Likely intentional` bucket: `Likely intentional` is triage's soft positive verdict; `❓` is reviewer's honest "I don't know." | ❓ emoji prefix |
>
>    **Sort order is 🔴 → 🟡 → 🔵 → ❓** (high, medium, nit, question). Rationale: GitHub collapses long review threads showing first-few and last-few comments — 🔴 is most urgent so it goes first, ❓ asks for an author response so it goes last (visible at the bottom), and 🔵 nits sit in the middle where it's fine if they get collapsed away.
>
>    **After picking sev from the table, apply these 5 heuristics in order to adjust. None of them transform a finding into `question` or away from `question` — `question` is the reviewer's honest uncertainty signal and only the initial bucket-and-grade pass assigns it.**
>
>    1. **Test code → one tier lower** than equivalent production-code finding. (Test logic actually broken stays at original tier; "test no longer exercises real path" is a logic break, not a downgrade case.)
>    2. **Lint-ignored / `@ts-expect-error` / `eslint-disable` → automatic 🔵 nit.** The author explicitly silenced it; surface for visibility, don't gate merge.
>    3. **Convention violation with widespread existing precedent → downgrade one tier.** Cite the precedent file in the finding body.
>    4. **Out-of-diff buckets (`Pre-existing`, `Outside change`) → cap at 🟡.** The PR isn't responsible for fixing them; never 🔴.
>    5. **`Likely intentional` bucket → cap at 🟡.** By definition the change appears deliberate; surfacing as 🔴 contradicts the bucket.
>
> 5. **Return** a JSON array of triaged findings, **sorted** 🔴 → 🟡 → 🔵 → ❓ (within each, group by bucket so inline-vs-body routing is contiguous):
>    ```
>    [{ "bucket": "Issue|Likely intentional|Pre-existing|Outside change",
>       "severity": "high|medium|nit|question",
>       "file": "<path>",
>       "line": <number>,
>       "side": "RIGHT|LEFT",
>       "description": "<final wording for the comment — without emoji prefix; the parent adds it>",
>       "evidence": "<citation>" }, ...]
>    ```
>
>    `side: "RIGHT"` for added lines, `side: "LEFT"` for removed/deleted lines.
>    For `Pre-existing` and `Outside change`, `line` is for reader context only — these are posted in the body, not inline.

## Step 7 — Skip-zero, re-check eligibility, hand off to posting reference

**If triage returns 0 findings total → exit silently. Don't post anything.**

Otherwise:

1. **Re-check eligibility.** Cheap bash repeat of step 2 — guards against the PR being closed/merged while the agents were running. If now ineligible, skip silently.

2. **Load `references/posting.md` and follow it.** That file is the authoritative spec for: pre-flight line validation against diff hunks, payload build, the `gh api` POST, the review-body markdown template, the inline-comment body template, and the known posting pitfalls (renamed-file partial diffs, `patch` truncation, PENDING-review traps). Do not improvise the posting logic — these rules were learned the hard way and the failure modes are silent.

## Tool preference order (for #1 and #2)

When two MCPs offer overlapping capabilities:

1. **TypeScript LSP** for TS/JS workspaces — type-aware references, hover types.
2. **code-review-graph MCP** — structural traversal across languages.
3. **grep + Read** — fallback.

Check tool availability by attempting to call the preferred tool; fall back on error. Don't pre-flight check.

## Skip conditions (summary)

| Condition | Action |
|---|---|
| PR closed | Skip silently |
| PR draft | Skip silently |
| Marker `<!-- custom-review:HEAD_SHA -->` matches current HEAD | Skip silently |
| Marker present with **different** SHA | Proceed (PR has new commits) |
| No PR found for current branch and no arg | Error message, exit |
| Zero findings after triage | Skip silently (no "no issues found" placeholder) |
| Only nit and/or question findings after triage | **Still post** — surfacing nits and questions is intentional |
| Re-check at step 7 fails | Skip silently (race with PR close) |

## What this skill explicitly does NOT do

- **Does not run** `pnpm lint`, `pnpm test`, `pnpm quality`, or any build/typecheck command. CI owns those signals; review findings that overlap with them are filtered as false positives.
- **Does not apply fixes.** This is a one-shot review, not a loop. For auto-fix on bot reviews, use `/pr-review-and-fix`.
- **Does not loop or retry.** Run once, post once, exit.
- **Does not post on closed/draft/already-reviewed PRs.** Step 2 enforces this.
- **Does not use Haiku.** No issue-scoring step. No Haiku-driven exploration before Opus agents.
- **Does not score 0–100.** Severity is a 4-way classification (🔴 / 🟡 / 🔵 / ❓) anchored to mergeability or reviewer-uncertainty, not numerical confidence. Triage's job is dedup + bucket + grade, not "is this a true positive 60%?"
- **Does not drop nits or questions.** Pre-severity behavior was "skip nitpicks / skip lint-ignored". New behavior grades them to 🔵 / ❓ and surfaces them so you can glance over.
- **Does not fabricate convention rules.** Agent #3 cites verbatim or stays silent.
- **Does not block on agent failures.** If an agent errors out, log the failure and continue with the remaining agents' findings. Note the missed coverage in the body footer (e.g. "Note: blast-radius agent failed; coverage may be incomplete.").

## Failure handling

- **Subagent crash:** continue with remaining agents. Add a one-line note to the review body footer indicating which agent failed.
- **Triage returns malformed output:** retry triage once with the same input. On second malformed output, fall back to posting all findings flat as `Issue` bucket inline (degraded mode) and note this in the body footer.
- **Posting failures (`gh api` 422 / 5xx / transient errors):** see `references/posting.md` § 3. In particular, **never bisect 422 errors by submitting more reviews** — every submitted-or-PENDING review on the PR is visible in the GitHub UI sidebar.

## Quick mental model

This skill replaces the upstream `code-review` plugin with:

- **No confidence scoring** (Haiku-too-dumb) — replaced by 1× Sonnet triage that dedupes, buckets, and grades severity.
- **4 buckets** instead of binary keep/drop — `Pre-existing` / `Likely intentional` / `Outside change` get surfaced with labels rather than filtered.
- **4-tier severity** — 🔴 block / 🟡 respond / 🔵 skip-and-merge / ❓ reviewer-uncertain (asks for author input). Orthogonal to buckets. Sort order 🔴 → 🟡 → 🔵 → ❓ so the GitHub auto-collapse hides nits in the middle, not questions. Triage applies 5 downgrade heuristics on 🔴/🟡/🔵 (test code, lint-ignored, widespread precedent, out-of-diff cap, Likely-intentional cap); heuristics never touch ❓ — it's the reviewer's honest "I don't know" signal.
- **Grade, don't drop.** Nits and lint-ignored findings surface as 🔵, genuine reviewer uncertainty surfaces as ❓ — rather than being filtered. The surface floor is just pure pedantry + CI-catchable + misread-diff.
- **Hybrid post format** — inline for in-diff findings, body collapsible for out-of-diff context. Severity emojis prefix every item.
- **Invariant checking** embedded in agents #2 and #4, not a separate agent.
- **LSP-first** for TypeScript impact analysis (agent #2) and signature confirmation (agent #1).
- **One-shot** — no loop, no auto-fix; pair with `/pr-review-and-fix` if you want bot-review-driven auto-fix afterward.
