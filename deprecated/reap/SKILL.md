---
name: reap
description: Router for the machine-hygiene reapers — stale git worktrees, orphaned dev-env procs/stacks, docker cruft — run in cascade order. Personal, user-invoked.
disable-model-invocation: true
---

# reap — machine-hygiene router

One entry point for reaping the cruft AI coding leaves on this machine. Three reapers,
each with its own mechanism and danger model — this skill says **which to run and in
what order**, then hands off. Run any one alone by its own name; run `/reap` to sweep
everything.

## The cascade

The reapers are **coupled**: reaping one tier orphans the next.

> reap a **worktree** → its dev-env **compose stack** loses its source dir (orphaned) →
> that stack's **docker volumes + networks** lose their container (orphaned)

So order matters — reap **outermost first**, let each stage surface the orphans the next
stage sweeps. Top to bottom:

1. **Worktrees** — reap merged/dead git worktrees. This is what *creates* the dev-env
   and docker orphans below, so it goes first.
2. **Dev-env** — reap orphaned host procs and the compose stacks step 1 just cut loose.
3. **Docker** — sweep the volumes/networks step 2 freed, plus generic build cache and
   unused images.

## Stages

Each stage is its own reaper. Run its scan first (read-only), present, reap on the
user's pick, then move down. A stage with nothing to reap prints empty — note it and
continue.

### 1. Worktrees → `/reap-stale-worktrees`
Follow that skill. It classifies every `.claude/worktrees/*` against its GitHub PR
(A merged / B closed / C stray-commit / D uncommitted-or-locked), backs up C/D, and
removes on confirm.
```bash
bash ~/.claude/skills/reap-stale-worktrees/reap-stale-worktrees.sh scan
```

### 2. Dev-env → `/reap-dev-env`
Follow that skill. It reaps host procs (auto worktree-gone orphans, asks on live) and
tears down orphaned compose stacks + their networks (`reap-stacks`) — exactly what
stage 1 just orphaned. Bare dangling volumes it leaves flow to stage 3.
```bash
CURRENT_ROOT="$(git rev-parse --show-toplevel)" bash ~/.claude/skills/reap-dev-env/reap-dev-env.sh scan
# then: reap-dev-env.sh reap <pids>   and   reap-dev-env.sh reap-stacks
```

### 3. Docker → `/reap-docker`
Follow that skill. It sweeps build cache + unused images (blanket-safe), and lists
dangling volumes **fingerprinted** — reap the throwaway ones by name, never a blind
`volume prune`. This clears the volumes/networks stage 2 freed plus generic cache/images.
```bash
bash ~/.claude/skills/reap-docker/reap-docker.sh scan
```

## Run one alone, not always all three

- worktree registry bloated / "clean up worktrees" → stage 1 only
- `next dev` leaks, port stuck, orphan procs → stage 2 only
- disk pressure, `docker df` fat → stage 3 only
- post-worktree-purge full sweep → all three, in order

## Shared guardrails

- **Scan before reap.** Every stage's scan is read-only. Look, present, confirm, then reap.
- **Explicit targets, never patterns.** Kill named PIDs / named paths / named docker
  objects, re-derived at reap time. No `pkill`, no argv match, no blind `prune` — those
  take every worktree's or project's objects at once.
- **Recovery net before irreversible loss.** Unmerged/uncommitted worktree work and any
  volume that might hold real data get backed up (or fingerprinted) before removal.
- **Codex leaves nothing** — `codex exec review` is in-place; `~/.codex/worktrees/` stays
  empty. No codex stage.

## Out of scope

AI-tool *state* — Claude session transcripts (`~/.claude/projects`), codex logs
(`~/.codex/logs_*.sqlite`), Conductor's DB — is a separate family (history, not orphans;
higher risk). Not a reap stage. Prune it by hand, deliberately.

Done when every stage you ran is either reaped or reported empty, and each removal has a
stated reason.
