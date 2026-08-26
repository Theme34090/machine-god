---
name: codex-review
description: "Get a second-opinion thermos code review from the codex CLI (external agent) on a diff, and optionally auto-fix its findings. Use when the user says 'codex review', 'have codex review this', 'second opinion review', 'thermos with codex', 'codex review and fix', 'loop fix', or wants an out-of-band reviewer on the current branch/PR/commit. Thin wrapper around the thermos skill run inside codex."
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Skill, TaskCreate, TaskUpdate
---

# codex-review

Shell out to the **codex** CLI to run a *thermos* review of the current diff, and
read back a clean verdict. This is a *second opinion from a different model*, not
a substitute for `/code-review`. The runner hides the codex footguns (stdin hang,
dir trust, 9k-line transcript, session tracking). You pick params, read the
printed result, and — in fix modes — act on it.

## Invoke

Args are **positional or flagged** — bare tokens are classified by value, so
`/codex-review luna low` just works.

```bash
bash ~/.claude/skills/codex-review/run.sh luna low          # model=gpt-5.6-luna, effort=low
bash ~/.claude/skills/codex-review/run.sh --effort high --target uncommitted
bash ~/.claude/skills/codex-review/run.sh resume            # re-review in the same codex session
```

All optional. Defaults shown.

| Param   | Default | Bare tokens / values                                                             |
| ------- | ------- | -------------------------------------------------------------------------------- |
| model   | `sol`   | alias `luna` \| `terra` \| `sol` → `gpt-5.6-*`; or full id; or `--model`          |
| effort  | `low`   | `low` \| `medium` \| `high` \| `xhigh` (codex reasoning, verbatim); or `--effort` |
| target  | `main`  | bare `main` \| `uncommitted`; branch/sha need `--target <ref>`                    |
| concern | none    | `--concern "<focus>"` only (multi-word); empty = codex infers                     |
| session | fresh   | `resume` = continue this branch's codex thread; `fresh` = force a new one         |

Bare branch/sha targets are flag-only (`--target`) to avoid misreading a model
alias or effort word as a ref.

There is only one review style: **thermos** (both passes + synthesis). The old
`normal` mode (codex's built-in `review`) is gone; `thermos` as a bare token is
accepted and ignored.

The script prints codex's final verdict, then the path to the full transcript.
**Read the printed verdict — do not cat the transcript** unless you need to
verify a specific claim. Every run ends with a machine-readable tail:

```
VERDICT: <SAFE TO MERGE|NEEDS CHANGES|BLOCKER>
REMAINING MUST-FIX: <n>
```

## Modes

The user picks the mode in their prompt. `fix` and `loop-fix` are **your** work,
not the runner's — strip those words before passing args through.

### review (default)

Run the script, verify the findings against the diff, present them. Then follow
the user's standing rule: run `/review-assist` to bucket the findings. Stop there.

### fix — `/codex-review fix`

1. Run the script (fresh session).
2. Verify each finding against the actual diff — see *Verify before trusting*.
   Drop the ones that don't survive.
3. Bucket the survivors through the **review-assist lens** (🔴 must-fix /
   🟡 should-fix / 🔵 nitpick — invoke `/review-assist` for the triage and the
   writeup).
4. Apply fixes for **must-fix and should-fix**. Leave nitpicks unless they are
   one-line and obviously safe.
5. Stop and report if a finding needs a product/design decision, or if the fix
   would restructure code well beyond the bug — surface it instead of guessing.
6. Report: what was fixed (file:line), what was skipped and why.

Do **not** re-review after fixing in this mode — that's `loop-fix`.

### loop-fix — `/codex-review loop fix`

Same as `fix`, then loop:

1. Apply the fixes.
2. Re-run with `resume` — same codex session, so it grades its own prior
   findings instead of starting cold:
   ```bash
   bash ~/.claude/skills/codex-review/run.sh resume --effort <same> --target <same>
   ```
3. Read `REMAINING MUST-FIX`. If `0` (or the verdict is SAFE TO MERGE), stop.
4. Otherwise verify → triage → fix the remaining must-fixes and loop.

**Stop conditions — obey all of them:**

- `REMAINING MUST-FIX: 0` / verdict `SAFE TO MERGE` → done.
- **Max 3 fix rounds.** Then stop and report what's left, even if non-zero.
- Codex re-raises a finding you deliberately rejected → do not fix it to make
  the loop terminate. Record the disagreement and stop.
- Fix requires a product decision, or the same finding survives two rounds of
  fixes → stop and hand back to the user.

Track rounds with TaskCreate/TaskUpdate so the loop state survives a compaction.

## Sessions

The runner records codex's session id per branch in the workspace's
`.context/codex-review/` (conductor creates `.context/` and it's already
gitignored, so the state dies with the workspace). Outside a conductor workspace
— no `.context/` present — it falls back to `~/.claude/state/codex-review/` keyed
by repo+branch; the runner never creates `.context/` itself. `CODEX_REVIEW_STATE_DIR`
overrides both. `resume` continues that thread; the reviewer
still remembers its own findings, so a re-review is a diff-of-a-diff rather than
a cold second opinion (cheaper, and it can say FIXED / PARTIAL / NOT FIXED).

- Re-review → default to `resume`. This is what loop-fix does.
- Only use `fresh` when the user explicitly asks for a fresh/clean/independent
  session, or the branch was rebased/rewritten so the old conversation describes
  code that no longer exists.
- `resume` with no recorded session falls back to a full fresh review (it says so
  in the header line).

## Reviewing a PR

The runner never touches git — it reviews the **current** repo state. To review a
PR, check it out first (isolate it so it doesn't collide with other work), then
run with the default `--target main`:

```bash
# in a scratch/second worktree, detached so no branch lock:
git fetch origin pull/<N>/head && git checkout --detach FETCH_HEAD
bash ~/.claude/skills/codex-review/run.sh --target main --effort low
```

## Verify before trusting

codex findings are a second opinion, not ground truth. Before reporting a finding
as real — and **always** before editing code for it — check it against the actual
diff (grep the claim, confirm the line). In past runs codex flagged a
real-but-harmless lockfile downgrade and a stale doc — both true, but severity was
the caller's call. In fix modes this gate is load-bearing: an unverified finding
becomes an unnecessary edit.

## Notes / footguns baked in

- `</dev/null` — codex `exec` hangs forever ("Reading additional input from
  stdin") when stdin is a pipe (which the Bash tool provides). Runner guards it.
- dir trust — non-cwd/worktree paths aren't in codex's trusted-projects; runner
  injects `-c projects."<repo>".trust_level=trusted` so exec never stalls on a
  trust prompt.
- clean output — runner uses `-o FINAL`; you read that, not the transcript.
- codex runs `-s workspace-write` (thermos wants scratch space). It reviews; it
  does not own the fixes — you do.
- session id is scraped from the transcript (`session id: <uuid>`); if codex ever
  stops printing it, `resume` degrades to a fresh review rather than failing.
- Target classification is naive: an all-hex branch name (e.g. `abcdef`) is read
  as a commit sha. Rare; pass an explicit sha or a non-hex branch.
