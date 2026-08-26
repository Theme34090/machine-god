---
name: reap-stale-worktrees
description: Audit and reap the stale agent/workflow git worktrees Claude leaves under <repo>/.claude/worktrees/ — classify each against its GitHub PR, back up unmerged work, remove PR-resolved residue. Personal, user-invoked.
disable-model-invocation: true
---

# reap-stale-worktrees — reap Claude's leftover git worktrees

Claude's Agent (`isolation: worktree`) and Workflow tools cut a git worktree under
`<repo>/.claude/worktrees/` per run. They auto-remove **only if left unchanged** — the
instant an agent commits (the deliverable), the worktree + branch are **kept** for you
to review. Nothing reaps them after you merge, so they silt up: dozens of `agent-*`,
`wf_*`, and ticket branches long after their PRs shipped or died.

The truth source is **GitHub PR state, not git ancestry** — squash-merge rewrites
commits, so a shipped branch reads "unmerged" to `git merge-base`. The scan asks `gh`.

## The one rule

Reap freely only what a PR already resolved — **tier A** (PR merged: residue, work is
in main) and **tier B** (PR closed: work dropped on purpose). Everything else holds
value that lives **only in that worktree** — **tier C** (a stray commit, no PR) and
**tier D** (uncommitted changes and/or a stale lock, no PR). C and D get a **recovery
net** (backup) *and* an explicit user pick before they die. Removing a worktree is
`--force`; there is no undo but the net.

Tiers:

- **A** — PR merged. Residue. Reap. (A worktree can still be dirty with junk, e.g. a
  stray screenshot — that needs `FORCE=1` but loses nothing.)
- **B** — PR closed unmerged. Work intentionally abandoned. Reap.
- **C** — no PR, clean, ≥1 commit ahead of main. Stale agent scratch, but that commit
  exists nowhere else. Back up, then user decides.
- **D** — no PR, **uncommitted files** and/or a **lock** held by a maybe-dead agent.
  May be the only copy of real work. Back up, then user decides. Never `FORCE=1` a D
  until its patch is on disk.

## Steps

Run from any checkout of the target repo; it operates on that repo's worktree registry.
Repeat per repo (paypers, paypers-landing, …) — one registry each.

1. **Scan** (read-only — never removes):
   ```bash
   bash ~/.claude/skills/reap-stale-worktrees/reap-stale-worktrees.sh scan
   ```
   One row per `.claude/worktrees/*` worktree — `TIER WORKTREE PR DIRTY AHEAD BRANCH` —
   then `SAFE_REAP_PATHS:` (tier A+B) and `DANGER_PATHS:` (tier D). Done when the table
   plus both path lists are printed. An empty table means the registry is already clean —
   stop and report that.

2. **Present the tiers** to the user, riskiest first (D, then C, then B, then A), one
   line each with worktree, PR, age/dirty, and why it might still matter. Recommend the
   obvious reap (all of A+B) and flag every C/D by name. Done when the user has the table
   and your recommendation and has chosen a reap set.

3. **Cast the recovery net** — only if the chosen set includes any C or D:
   ```bash
   bash ~/.claude/skills/reap-stale-worktrees/reap-stale-worktrees.sh backup <backup-dir>
   ```
   Writes `branch-tips.txt` (every branch SHA — recover via `git branch <name> <sha>`)
   and a `<name>.uncommitted.patch` for each dirty worktree. Done when the backup dir
   holds a tips file and one patch per dirty worktree the user is about to reap. Skip
   this step only when the reap set is pure A+B.

4. **Reap the confirmed paths** — pass exactly the paths the user picked from the scan
   (the `SAFE_REAP_PATHS` value for A+B; individual C/D paths on top). C/D and any dirty
   worktree need `FORCE=1`:
   ```bash
   bash ~/.claude/skills/reap-stale-worktrees/reap-stale-worktrees.sh reap <paths>
   FORCE=1 bash ~/.claude/skills/reap-stale-worktrees/reap-stale-worktrees.sh reap <dirty-or-CD-paths>
   ```
   The reaper refuses any path outside `.claude/worktrees/`, then unlock → `remove
   --force` → `branch -D` each. A large set is slow (~10-15s/worktree) — run it
   backgrounded and wait for exit rather than letting a foreground call time out. Done
   when it prints `reaped N` and a re-`scan` shows every chosen row gone.

5. **Report**: what was reaped, what was kept and why, the backup dir path, and any
   non-worktree leftovers the scan sat beside (a stray dir with no `.git`, e.g. an
   orphaned `.next` cache — name it, don't remove it without the user's word).

Done when every row the scan printed is either reaped or kept with a stated reason.

## Guardrails

- **PR state, not ancestry.** Never trust `git merge-base`/`--is-ancestor` to call a
  branch merged — squash hides it. The scan's tier is the authority.
- **Explicit paths only.** Reap acts on the literal paths given, each re-validated to
  live under `.claude/worktrees/`. Never a name pattern — the primary checkout and the
  Conductor city workspaces share the registry and must never be touched.
- **`FORCE=1` is the dirty/locked gate.** Without it the reaper skips any worktree with
  uncommitted changes or a lock, so a D can't die by accident. Set it only after step 3.
- **Codex leaves nothing.** `codex exec review` reviews in-place; `~/.codex/worktrees/`
  stays empty. No codex counterpart to reap.
