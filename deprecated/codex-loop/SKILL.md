---
name: codex-loop
description: Run a review-and-fix loop where Codex (GPT-5.5) audits Claude's work as a fresh-eyes reviewer, a triage subagent classifies findings into must-fix/should-fix/invalid, and Claude applies must-fixes. Default budget 2 rounds (configurable from the user's argument — e.g. "simple" → 1, "thorough" → 3, "until clean" → uncapped). Use when the user says "codex loop", "codex review and fix", "validate with codex", "loop with codex until clean", or any variant. User-invoked only.
---

# Codex Loop

## Purpose

A review-and-fix loop with three roles:

- **Codex** (GPT-5.5, fresh-eyes auditor): different model family, different training, different biases — catches things Claude is blind to precisely *because* Claude implemented them. Surfaces findings; doesn't decide what to do with them.
- **Triage subagent** (fresh-context Claude Opus): classifies each finding into must-fix / should-fix / invalid by reading the cited code itself. Hasn't seen the implementer's reasoning, so it can't rationalize findings away.
- **Main Claude** (the implementer): applies must-fixes narrowly, defers should-fixes that don't fit the PR, surfaces product/contract calls to the user.

The triage subagent is the routine decision point. Step E's runtime-correctness escalation is the only path where Codex and main Claude can deadlock — and it surfaces to the user rather than silently picking a winner.

## When to run

User-invoked. Typical entry: Claude has just planned/implemented something non-trivial and the user says "codex loop" (or variant). Do NOT auto-trigger.

## Before round 1

1. **Detect base branch** for the diff scope. Default: `git symbolic-ref --short refs/remotes/origin/HEAD | sed 's@^origin/@@'`, fall back to `main`. If the current branch equals the base branch, use `--scope working-tree` instead of branch diff.
2. **Detect project quality gate**: read `package.json` scripts, `Makefile`, `justfile`, or repo `CLAUDE.md` to identify the command that runs type-check/lint/tests. If none found, run whatever the repo conventionally uses; if still unclear, ask the user once.
3. **Verify Codex is set up** — run `npx -y @openai/codex --version` once to warm the npm cache. If the command fails, or `~/.codex/auth.json` does not exist, tell the user to run `npx -y @openai/codex login` and stop. Auth state in `~/.codex/auth.json` persists regardless of how Codex was previously installed (brew, global npm, npx).
4. **Pick round budget from the user's argument.** Default: **2**. Tighten or loosen based on cadence words in the prompt:
   - "simple", "quick", "read through", "sanity check", "one pass" → **1**
   - "look", "review", no qualifier → **2** (default)
   - "thorough", "deep review" → **3**
   - "until clean", "loop until done" → **uncapped** (still subject to the other Termination conditions — oscillation, scope blow-up, inconclusive standoff)

   The argument is the user's cadence vote. Don't override silently. If you reach the budget and a real must-fix remains, surface it and ask before extending — don't auto-extend.

## Per-round decisions (state aloud before acting)

Each round, announce these three choices in 2-4 lines before invoking Codex:

### 1. Codex surface

Pick one based on what the round is for, not habit:

- **`review`** — broad defect sweep. Default for round 1 when there's no specific worry. No focus text supported.
- **`adversarial-review <focus>`** — Claude has a **named** concern (an assumption, a tradeoff, a concurrency path, a boundary, a specific file). Write focus text narrowly, e.g. `"challenge whether the advisory lock prevents double-credit under retry — see services/payments/lock.ts and the retry wrapper in utils/retry/core.ts"`. This is the main steering lever.
- **`rescue --write` (task)** — sparingly. Use when Claude wants Codex to produce a **second draft** of an implementation, a **failing reproducer test**, or a **diagnosis** on a part Claude is stuck on. Not for routine review.

### 2. Scope

- `--base <detected-base> --scope branch` (default once on a feature branch)
- `--scope working-tree` if on main or no divergence
- Focus narrows semantically via `adversarial-review`'s focus text — there's no path filter flag

### 3. Execution mode

Foreground only. Block on each Codex invocation, capture its final message to a file, and move to triage. No background jobs — there is no companion runtime to track them. For large round-1 diffs you'll wait through the Codex run; use that idle time to re-read the plan/spec, run the quality gate, and draft Step A's self-check before the result lands.

## Round structure

### Step A — pre-round self-check (mandatory)

Before invoking Codex, write 2-3 sentences:
- what I implemented in scope
- what I'm unsure about
- what I'd attack if I were Codex reviewing this

This seeds adversarial focus text and prevents "just run review and wait." **If the round is adversarial, the self-check's third sentence should drive the focus text.**

### Step B — invoke Codex

Shell out directly to `npx -y @openai/codex exec`. Always capture the final agent message to a file via `--output-last-message` so triage (Step C) reads a clean artifact, not a mix of progress chatter and the result.

Substitute `<sanitized-branch>` (replace `/` with `-`) and `<R>` (round number) into the output paths below.

```bash
# generic review — built-in reviewer, no focus text (runtime config defaults)
npx -y @openai/codex exec review \
  --base <base> \
  --output-last-message /tmp/codex-loop-<sanitized-branch>-round-<R>.md

# adversarial review — same reviewer, custom focus text appended
npx -y @openai/codex exec review \
  --base <base> \
  --output-last-message /tmp/codex-loop-<sanitized-branch>-round-<R>.md \
  "<focus text>"

# working-tree scope (on the base branch, or no divergence) — swap --base for --uncommitted
npx -y @openai/codex exec review \
  --uncommitted \
  --output-last-message /tmp/codex-loop-<sanitized-branch>-round-<R>.md \
  "<focus text or omit>"
```

For **rescue** (second-draft implementation / reproducer test / stuck-point diagnosis), invoke `codex exec` directly with pinned model and reasoning effort. Pick the sandbox by intent:

```bash
# read-only rescue — diagnosis or second-draft idea without applying edits
npx -y @openai/codex exec \
  -m gpt-5.5 -c model_reasoning_effort=xhigh \
  -s read-only \
  --output-last-message /tmp/codex-loop-<sanitized-branch>-rescue-<R>.md \
  "<prompt text>"

# write-capable rescue — let Codex apply edits in the workspace
npx -y @openai/codex exec \
  -m gpt-5.5 -c model_reasoning_effort=xhigh \
  -s workspace-write \
  --output-last-message /tmp/codex-loop-<sanitized-branch>-rescue-<R>.md \
  "<prompt text>"
```

After the command returns, Read the `--output-last-message` file and feed its contents into Step C as the raw Codex output.

Notes:

- `npx -y @openai/codex` is slower than a directly-installed binary on first invocation (downloads/extracts the package); subsequent runs use the npm cache. Do not speculatively run `--help` or exploratory args — every invocation is a real run.
- `codex exec review` does NOT accept `-m`/`--model`; let the configured default stand. `codex exec` (rescue) does accept `-m` and `-c model_reasoning_effort=…` overrides.
- If `gpt-5.5` is rejected (model rename, account access), drop `-m` and fall back to the user's `~/.codex/config.toml` default.

### Step C — triage findings (fresh-context subagent)

Dispatch one Agent call:

- `subagent_type`: `general-purpose`
- `model`: `opus` (resolves to whichever Opus is current in this environment — Opus 4.7 at time of writing; pinned to Opus, never Sonnet/Haiku)
- `description`: e.g. "Triage codex-loop round <R> findings"
- `prompt`: see template below — note the prompt starts with `ultrathink` to engage maximum extended-thinking budget for the classification step

Why a subagent: it starts with fresh context. It hasn't seen the implementer's reasoning, so it's harder for it to rationalize away findings than the implementer is. Throwing away triage context between rounds also keeps the main thread lean.

The subagent only classifies into three buckets: **must-fix**, **should-fix**, **invalid**. It does NOT decide whether a should-fix applies this round vs later, and it does NOT decide whether a fix is a product/contract call — those are main-agent decisions in Step D.

#### Triage prompt template

````
ultrathink

You are triaging findings from Codex on branch <branch> against base <base>.

Here is the raw Codex output:

<paste the full `# Codex Review` or `# Codex Adversarial Review` block>

If a decisions log exists at /tmp/codex-loop-<sanitized-branch>-decisions.md,
read it first. Any finding that textually matches a previously-logged
decision should be classified as `invalid` with reason "previously decided
in round <N> — see decisions log". Do not re-litigate. If the finding is
genuinely new (different file or different issue), proceed with normal
verification.

## Mandatory verification process

For EACH finding that cites a file:line you MUST:

1. Read the file at the referenced line range using the Read tool (~10
   lines of context on each side). Do not classify from Codex's text
   alone — Codex can misread, and line numbers drift between Codex's
   git-diff snapshot and the current tree.
2. If the cited line doesn't match Codex's description, do NOT
   immediately reject. Grep the file for the described pattern
   (function name, variable, distinctive string). If the issue exists
   at a different line, classify based on the real code; cite the
   stale Codex line for reference.
3. Only classify as `invalid (could not reproduce)` when the described
   behavior genuinely doesn't exist anywhere in the file (or the file
   doesn't exist).
4. Only after verification, decide the bucket grounded in the code you
   actually located.

One finding at a time: read, decide, write the entry, move on. No
batching reads across findings. Codex's confidence in its own finding
does NOT substitute for verification.

## Buckets

- **must-fix**: a real bug introduced or touched by this branch's diff —
  correctness, security, auth/authz gap, data corruption, crash,
  regression, missing validation at a trust boundary, race/TOCTOU — OR
  a trivially in-scope extension of touched code (≤5 lines, same file,
  same concern).

- **should-fix**: codebase-health improvement on touched code —
  refactors, DRY, naming, small test gaps, nits. Not a bug; doesn't
  affect correctness/security. Do NOT pre-decide whether it ships in
  this PR vs later — the main agent decides.

- **invalid**: out-of-scope (pre-existing on the base branch and this
  branch's diff didn't touch it), Codex misread, by-design per
  docstring/comment, style preference contradicting the codebase, a
  consistency-only suggestion with no correctness consequence
  ("do X like the other call site" where the value is fixed and can't
  break the behavior), `could not reproduce` per verification, or a
  textual match against the previous-round decisions log.

Consistency-only findings ("do X the same as line Y") with no
correctness consequence are always `invalid`. Do not upgrade based on
"≤1-line" or "Codex flagged it confidently"; those heuristics only
apply to real bugs.

## Output format

For EVERY must-fix and should-fix entry, the entry MUST include a
fenced code block containing the EXACT lines from the Read output
(copy-paste, do not paraphrase, do not use Codex's suggested fix).
This is the evidence that you actually looked at the code. An entry
without a quoted snippet will be rejected.

Entry format:

- `file:line` — one-sentence reason grounded in the quoted code.
  ```<language>
  <2-5 lines copied verbatim from Read output>
  ```

For invalid entries, include a one-sentence reason (or the literal
phrase `could not reproduce at <loc>` for verification failures).

Output as three markdown sections: `## must-fix`, `## should-fix`,
`## invalid`. Empty sections are fine.
````

Save the subagent's output verbatim to `/tmp/codex-loop-<sanitized-branch>-triage-round-<R>.md`.

### Step D — decide, apply, log

Walk the triage output top to bottom.

**For each must-fix:**

1. Read the code yourself — triage can misjudge. If on inspection the finding is invalid (already handled, scope-creep into untouched files, or cosmetic "consistency" upgrade), override to invalid and note the reason in the decisions log.

2. **Product-decision gate.** Before applying, ask: does this fix require choosing between defensible alternatives, or change user-visible output / an established product contract? Triggers for surfacing:
   - User-visible copy, error/toast wording, empty-state text
   - UI state changes, redirect targets, default values, sort/filter defaults
   - Error-handling contract changes (throw vs return null vs toast, status codes)
   - API response shape, webhook payload structure
   - Business rule interpretation ("expired", "active", "eligible")

   If **yes** → surface, don't apply. Log as `[surfaced]`. Include in the final report under "Needs your call".

   If **no** → apply narrowly. No surrounding cleanup.

   Examples of auto-fix (one correct answer): missing `userId` filter on a user-owned-resource query, null guard on a crash path, forgotten `await` causing a race, missing field in a Zod schema already required elsewhere, log/comment typo, dead import.

   Examples of surface (multiple defensible answers): "throw instead of returning empty list" (changes contract), "change Thai wording of error toast" (user-visible copy), "default sort should be ascending not descending" (product call), "expired trial should block feature X, not show banner" (business rule).

3. Otherwise, apply narrowly.

**For each should-fix:** apply-or-defer is the main agent's call. Lean apply when: change is ≤~15 lines on touched code, clearly improves health, doesn't require new tests or new abstractions. Lean defer when: it touches code this branch didn't modify, it's a cross-file refactor, it requires new test coverage, or it would meaningfully bloat the diff.

**For each invalid:** nothing to apply, but still log it.

**Log decisions.** Append (or create on round 1) `/tmp/codex-loop-<sanitized-branch>-decisions.md`:

```markdown
## Round <R> — <YYYY-MM-DD>

- [applied] <file:line> — <short description>
- [applied-should-fix] <file:line> — <short description>
- [surfaced] <file:line> — <short description> — <why it needs user judgment>
- [declined-should-fix] <file:line> — <short description> — <why declined>
- [invalid] <file:line> — <short description> — <why invalid>
```

Round N+1's triage reads this log and treats `[surfaced]` entries the same as other previously-decided entries — don't re-raise them.

The decisions log is a per-branch scratch file (not committed). Sanitize the branch name by replacing `/` with `-`.

**Then run the detected quality gate** before closing the round. Do NOT claim a finding is fixed if the gate fails — iterate until green.

### Step E — runtime-correctness escalation (rare, narrow)

This is the only path where Codex and Claude can deadlock instead of the triage subagent making the call. Use ONLY when ALL of:

- The finding is a **runtime correctness or concurrency claim** (race, ordering, deadlock, retry-double-execute, lock semantics, transaction boundary)
- Triage marked it invalid OR the main agent overrode triage to invalid
- Claude has a non-trivial reason it isn't a bug (framework guarantee, test coverage, code path doesn't reach)
- The disagreement matters enough to settle (it's not cosmetic)

For non-runtime findings (CSP, lint, convention, config, naming, type-safety, scope-width, env-gating, style) the triage subagent's verification + main-agent override IS the only escalation. Do not invoke this step.

Steps:

1. **Pushback** — resume the last Codex session and challenge the finding:

   ```bash
   npx -y @openai/codex exec resume --last \
     -m gpt-5.5 -c model_reasoning_effort=xhigh \
     -s read-only \
     --output-last-message /tmp/codex-loop-<sanitized-branch>-escalation-<R>.md \
     "I'm Claude. I marked your finding \"<brief>\" as invalid because <reasoning with file:line evidence>. Reconsider: is your finding still load-bearing? If yes, state why my evidence is wrong. If no, retract."
   ```

2. **If Codex retracts** → invalid, move on.

3. **If Codex insists** → reproducer-evidence round (final tiebreaker). Resume the same session and ask for code:

   ```bash
   npx -y @openai/codex exec resume --last \
     -m gpt-5.5 -c model_reasoning_effort=xhigh \
     -s workspace-write \
     --output-last-message /tmp/codex-loop-<sanitized-branch>-reproducer-<R>.md \
     "We disagree. Settle it with code. Produce a minimal failing test or reproducer that demonstrates the bug. If you cannot produce one, retract."
   ```

4. **Run the reproducer:**
   - Fails on current code → Codex was right, fix it.
   - Passes / doesn't demonstrate the bug → Claude was right, invalid.
   - Codex refuses or produces an ambiguous reproducer → **surface to user** with both sides' reasoning. Do NOT pick a winner.

### Step F — compose round N+1 focus text

If the round budget allows another round, build the focus text for the next `adversarial-review` from concrete round-N artifacts (NOT from Claude's brain-storming about new fragility — past runs show the implementer is in classification mode by round 2 and cannot generate useful attack angles):

1. **Re-attack this round's fixes.** For each `[applied]` and `[applied-should-fix]` entry in the decisions log, name the file:line and the assertion the fix relies on. Ask Codex to challenge the assertion. Example: `"the new util at apps/frontend/utils/image-url.ts assumes GCS V4 signed URLs always carry X-Goog-Signature= or X-Goog-Algorithm=. Find a real GCS or fake-gcs-server configuration where they don't."`

2. **Re-attack overrides.** For each finding triage or main-agent marked `invalid` that wasn't a clear misread, briefly state the counter-reasoning and ask Codex to find a counterexample. Example: `"you flagged the NEXT_PUBLIC_APP_ENV gate as build-bake-risky; we deferred because the existing localConnectSrc uses the same pattern. Find a real build path where the gate would leak the relaxed CSP into a production artifact."`

3. **Probe the unprobed.** Append verbatim: `"What attack surface did you NOT inspect in round <N>? Name files or concerns you skipped, then attack them. Be specific about what you did read and what you didn't."`

The composed focus text is the input to round N+1's Step B (adversarial-review). Skip Step F if the round budget is exhausted — there's no next round to seed.

## Termination

Stop and produce the final report when any of:

1. **Clean round + empty closing self-check** — no must-fix, no should-fix, Claude has no new worries. Done.
2. **Round budget reached** — budget set in `Before round 1` step 4 (default 2). Report remainder as deferred. Do not auto-extend; surface to the user if a real must-fix remains.
3. **Oscillation** — the same finding returns after a claimed fix. Stop, surface — something is structurally wrong in the fix approach.
4. **Reproducer-round inconclusive** — tie not breakable by code. Surface.
5. **Out-of-scope blow-up** — more than 3 findings outside the task area. Stop, surface, let the user decide whether to widen scope.

## Final report

Structured, terse. Include:

- **Rounds run** (N of max)
- **Per round**: surface chosen + one-line rationale, scope, execution mode, findings count by bucket, fixes applied, defers with reason, invalidations with evidence, any standoffs and how resolved
- **Open items**: deferred findings, surfaced standoffs, out-of-scope items
- **Final state**: clean / max-rounds / standoff / oscillation / scope-blowup

Keep it scannable — headers + short bullets, not prose.

## Operating notes

- **Model/effort discipline**: always `-m gpt-5.5 -c model_reasoning_effort=xhigh` on rescue calls. Review (`codex exec review`) does not accept `-m` — let the configured default stand.
- **Foreground only**: every Codex invocation blocks this turn. There is no background job runtime in this skill; do not try to launch one or poll for status.
- **Prompt style for rescue**: follow the `codex:gpt-5-4-prompting` skill (compact, XML-tagged, explicit output contract) when shaping rescue prompts. Apply it inline — this skill no longer routes through the `codex:codex-rescue` subagent.
- **Do not speculatively invoke `npx -y @openai/codex`** for `--help` or exploration — `codex exec` treats unknown args as a real prompt and starts a real run. The one allowed warm-up call is the `--version` check in "Before round 1" step 3.
- **Auditor framing in prompts**: when invoking Step E's pushback / reproducer escalation, address Codex as a peer for that specific exchange ("we disagree", "settle it with code"). Outside Step E, Codex's findings are audit input — useful but not authoritative — and the triage subagent classifies them.
- **Never silently pick a winner on standoffs.** Surface to the user. That is a load-bearing property of this skill.
