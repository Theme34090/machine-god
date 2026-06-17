---
name: custom-mini-review
description: Fast pure-code mini code review for active dev loops — runs after a commit or implementor-agent finishes a unit of work. Surfaces findings in caveman dialect with 4-tier severity (🔴 bug / 🟡 risk / 🔵 nit / ❓ q) and in-diff/out-of-diff annotation. Pure guidance — orchestrator decides whether to delegate execution to a subagent, codex, or run inline. Counterpart of `/custom-review` (heavy multi-agent quality gate before merge). Use when the user says "mini review", "custom-mini-review", "quick review", "/custom-mini-review", or invokes after a commit or implementor agent.
---

# custom-mini-review

Fast first-pass code review for active dev loops. Pure code reasoning, no intent bias. Caveman dialect output.

This skill is **guidance only** — it tells the reviewer what to look for, how to scope, and how to format findings. The orchestrator invoking the skill decides *how* to execute (inline, fresh-context subagent, codex CLI, etc.).

Counterpart of `/custom-review` (multi-agent quality gate before merge). Reach for the heavy one when blocking merge; reach for this one inside the dev loop.

## When to invoke

- After a commit, to get instant feedback on what just landed.
- After an implementor subagent returns, to validate the unit of work.
- Whenever the user types `/custom-mini-review [args]`.

## When NOT to invoke

- Pre-merge quality gate → `/custom-review`.
- CI failure investigation → appropriate debug skill.
- Single-line typo → just read the diff.

---

## Step 1 — Gather the diff

Arg forms (in priority order):

| Arg | Meaning |
|---|---|
| `<sha>` | Review that commit: `git show <sha>` |
| `--staged` | Review staged changes: `git diff --staged` |
| `--branch` | Review whole branch vs main: `git diff main...HEAD` |
| `--scope=cascade` | Force cascade scope (see Step 2) |
| `<files...>` | Filter to just those paths (intersection with diff) |
| *(no arg)* | Default: uncommitted-if-any (`git diff` + staged + untracked), else `git show HEAD` |

**Edge cases:**

- Zero diff in scope → print `no diff in scope. nothing to review.` and exit 0.
- Binary files → skip them. Note in header: `binary: N skipped`.
- Merge commit at HEAD with no own changes → fall back to `git show --first-parent HEAD`. Note in header.
- Untracked files in default scope → include as new (diff against `/dev/null`).

---

## Step 2 — Pick scope (HEAD / branch / cascade)

Scope determines how far the reviewer looks beyond the diff itself.

| Scope | Reviewer looks at |
|---|---|
| **HEAD** | Only lines in the diff |
| **branch** | Diff + caller-side invariants for changed symbols (1 hop out) |
| **cascade** | Diff + callers + sibling code in same file + adjacent files in same module |

**Auto-escalate from HEAD → branch/cascade when ANY of these fire:**

- An exported symbol's signature changed (return type, params, throw semantics, sync↔async).
- Diff touches `lib/`, `utils/`, `services/shared/`, or any shared package.
- Multiple files in different domains (e.g. api + frontend, or 3+ modules).
- A type / interface used elsewhere in the repo is modified.
- A migration / schema file is in the diff.

If none fire → stay at HEAD scope.

`--scope=cascade` arg force-overrides escalation upward. Reviewer notes the picked scope in the header line.

---

## Step 3 — Reason from first principles

**No intent context.** Do NOT read the commit message, PR title, or task description. Reason only from the code itself.

The goal is bias-free review: surface anything that doesn't make sense when looking at the code alone. If the change is deliberate but indistinguishable from a bug to a fresh-eyes reader, that's a finding — the author can dismiss it.

---

## Step 4 — Apply project priors

If `$PROJECT/.claude/mini-review-gotchas.md` exists, read it. Each line is `<rule>. why: <reason>.`.

Treat each rule as a **prior** — something to watch for as you read the diff. Do NOT treat as a checklist (don't force a finding per rule). Findings emerge naturally; the gotchas just sharpen attention.

If the file does not exist, skip silently. Apply only first-principles engineering judgment.

The skill does not ship a baked-in universal focus list. The reviewer's priors come entirely from the per-project gotchas file. New projects start empty and accumulate rules over time via the save-suggestion loop in Step 6.

---

## Step 5 — Format findings

**Output template:**

```
mini-review (scope: <HEAD|branch|cascade>, files: N, findings: N[, binary: N skipped])

<file>:L<n> [out-of-diff]? <emoji> <severity>: <problem>. <fix>.
...

# proposed gotcha (review before save)
"<rule>. why: <reason>."
append to .claude/mini-review-gotchas.md
```

**Severity tiers:**

- 🔴 `bug` — broken behavior, will cause incident
- 🟡 `risk` — works but fragile (race, missing guard, swallowed error)
- 🔵 `nit` — style, naming, micro-optim
- ❓ `q` — genuine question, can't tell from code alone

**Location tag:**

- In-diff finding → no tag.
- Finding on a line NOT modified by this diff (sibling fn, caller, adjacent code) → `[out-of-diff]` prefix.

**Sort order:**

1. By severity: 🔴 > 🟡 > 🔵 > ❓.
2. Within each tier: in-diff first, then `[out-of-diff]`.
3. Within those: by file path, then line.

**Header rules:**

- `scope:` matches Step 2 pick.
- `files:` count of files with at least one finding.
- `findings:` total count after sorting.
- `binary: N skipped` appears only if any binary files were skipped.

**Drop (the surface floor):**

- Throat-clearing ("I noticed", "It seems like", "You might want to consider").
- Restating what the line does — reader can read the diff.
- Hedging ("perhaps", "maybe"). If genuinely unsure → use `❓ q:`.
- CI-catchable issues (formatting, missing imports, type errors a linter / compiler catches).
- Pure pedantry a senior reviewer wouldn't even mention (variable rename for taste, optional helper extractions with no measurable benefit).

**Keep:**

- Exact line numbers.
- Symbol / function / variable names in backticks.
- Concrete fix, not "consider refactoring this".
- The *why* if the fix isn't obvious from the problem statement.

**Example findings:**

```
apps/api/src/services/foo.ts:L42 🔴 bug: user can be null after `.find()`. add guard before `.email`.
apps/api/src/services/foo.ts:L88 🟡 risk: no retry on 429. wrap in `withBackoff(3)`.
apps/api/src/services/foo.ts:L120 [out-of-diff] 🟡 risk: sibling fn `validateLegacy` has same gap. update or remove.
apps/api/src/services/foo.ts:L201 🔵 nit: hardcoded `#E1E5ED`. use `FLEX_UI_COLORS.separatorLight`.
apps/api/src/services/foo.ts:L33 ❓ q: is this `as unknown as Message` cast intentional? pre-existing per blame.
```

---

## Step 6 — Propose a gotcha (optional)

After emitting findings, decide whether to propose ONE new project-gotcha entry. **Cap = 1 per run.** Pick the highest-confidence candidate.

**Propose when (any):**

- A finding maps to a project-specific API / pattern misuse (e.g. raw throw vs domain error type, missing convention helper, wrong logger, wrong money type).
- A finding represents a structural antipattern (X-without-Y shape, missing-guard recurring across the codebase, async path without idempotency, etc.).
- A finding matches an existing entry in `mini-review-gotchas.md` with a tighter / broader rule → propose tightening that entry instead of a new one.

**Do NOT propose when (any):**

- Finding is a one-off bug (typo, off-by-one, transposed args).
- Finding is pure style / naming.
- A near-identical entry already exists in `mini-review-gotchas.md`.
- All findings were 🔵 nit / ❓ q only.

**Format:**

```
# proposed gotcha (review before save)
"<rule>. why: <reason>."
append to .claude/mini-review-gotchas.md
```

The user appends manually if they agree. No auto-save. No prompt to confirm.

If no candidate fires, omit this block entirely.

---

## Step 7 — Exit

Emit the formatted output to stdout. Skill is done. Orchestrator forwards to user / next agent / downstream triage as it sees fit.

---

## Project gotchas file format

`$PROJECT/.claude/mini-review-gotchas.md` is one bullet per gotcha, `<rule>. why: <reason>.` shape per bullet.

Example:

```
# project gotchas (read by /custom-mini-review)

- services/* — use `AppError` not raw throw. why: error codes need typed surface for frontend.
- prisma findFirst/findUnique on user-owned resource — always filter `userId`. why: critical multi-tenant leak.
- monetary fields — Prisma `Decimal` not `Float`. why: VAT precision (10.10 vs 10.1000000001).
- date math — `date-fns` funcs, never raw +/-. why: DST / TZ footguns.
- logging — Winston, never `console.log`. why: console bypasses log shipper.
```

Commit or `.gitignore` the file at your discretion. Reviewer reads it as priors alongside the 13 universal areas.

---

## What this skill explicitly does NOT do

- **Does not run** `pnpm lint`, `pnpm test`, build, or typecheck. CI owns those signals.
- **Does not apply fixes.** Detection only. A downstream triage skill decides what to fix.
- **Does not spawn subagents.** Pure guidance; orchestrator owns execution.
- **Does not read `AGENTS.md` / `CLAUDE.md`.** Too noisy for fast loop. Project quirks live in `mini-review-gotchas.md`.
- **Does not read the commit message / PR title / task description.** Pure first-principles code reasoning, no intent bias.
- **Does not auto-save gotchas.** Proposes one; user appends manually.
- **Does not bail on large diffs.** Reviews any size. Heavy diffs better served by `/custom-review`, but mini still runs.
- **Does not prescribe tools** (LSP, code-graph, grep). Orchestrator picks based on its own context.
- **Does not score 0–100.** Severity is the 4-tier caveman set, not numerical confidence.
- **Does not drop nits.** All findings surface. Downstream triage decides what to fix.

---

## Quick mental model

Caveman-review + scope-aware reading + per-project priors + save-suggestion loop.

- **Fast**: one pass, single executor (orchestrator's choice).
- **Bias-free**: no intent context.
- **Signal-first**: caveman dialect, terse format, no praise, no hedging.
- **Generic skill**: zero universal focus list. All priors come from per-project `mini-review-gotchas.md`.
- **Learning loop**: proposes one gotcha per run when a pattern recurs.
- **Counterpart to `/custom-review`** — that one is the merge gate; this one is the dev loop.
