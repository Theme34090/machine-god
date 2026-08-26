---
name: reap-dev-env
description: Find and surgically reap orphaned / stale / old Paypers dev-env host procs (next / api / admin) and orphaned compose stacks + networks across every worktree — auto-reaps only worktree-gone orphans, asks before killing anything still alive. Personal, user-invoked.
disable-model-invocation: true
---

# reap-dev-env — reap stray Paypers dev-env processes

Paypers dev-env runs a per-worktree stack (next / api / admin + the turbo/tsx/esbuild
chain) on offset ports. Across many worktrees they leak: a deleted worktree orphans
its chain (reparented to launchd), a crashed stack leaves half-dead workers, an old
`next dev` runs for days. The dev-env's own reaper
(`scripts/lib/dev-env-common.sh` → `reap_orphan_paypers_procs`) only sees
`paypers/worktrees/` **and** only fires during a dev-env action — so
Conductor-workspace orphans, and any machine where no dev-env command runs, never get
swept. This sweeps all of it, by hand. Invoke from any checkout; it reaps machine-wide.

## The one rule

Only an **orphan** — a proc whose worktree directory is gone — gets reaped without
asking; a proc with no worktree cannot be in use. Everything still alive (CURRENT /
TUNNEL / STALE / OLD / LIVE) is shown to the user and reaped only on their pick. Kill
targets are always explicit PIDs from the scan — never a `pkill` / argv pattern, which
murders every worktree's frontend at once (the path-scoped-kill rationale is documented
in `scripts/lib/dev-env-common.sh`).

## Steps

1. **Scan** (read-only — never kills):
   ```bash
   CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
     bash ~/.claude/skills/reap-dev-env/reap-dev-env.sh scan
   ```
   One row per worktree root — `STATE ROOT ROLE PORTS AGE PIDS` — then an
   `AUTO_REAP_PIDS:` line and any adjacent leftovers: orphaned compose stacks, the
   **Running paypers stacks** table (live, not-orphaned stacks oldest-first — the "up 11
   days but forgotten" teardown candidates), and stale `.next/dev/lock` with a dead pid.
   `CURRENT_ROOT` marks the invoking worktree so its stack is never auto-reaped.
   Widen/narrow the OLD cutoff with `OLD_DAYS=N` (default 2).

2. **Auto-reap orphans.** If `AUTO_REAP_PIDS` is non-empty, reap it now — those procs
   are worktree-gone and cannot be in use:
   ```bash
   bash ~/.claude/skills/reap-dev-env/reap-dev-env.sh reap <AUTO_REAP_PIDS>
   ```

3. **Present the living rows** to the user, oldest first, one line each with root, role,
   age, and why it might still matter:
   - **CURRENT** — the worktree you're in. Keep unless the user says otherwise.
   - **TUNNEL** — the tunnel-env singleton (base ports 3000/8080/3001). Reaping it drops
     live LIFF QA — confirm hard.
   - **STALE** — no listener; a half-dead leftover. Safe to reap, still confirm.
   - **OLD / LIVE** — a running stack in another worktree, maybe in active use. Confirm.
   Recommend the obvious reaps (STALE, and OLD nobody is using) but let the user choose.

4. **Reap the confirmed PIDs** — pass exactly the PID set(s) the user picked from the table:
   ```bash
   bash ~/.claude/skills/reap-dev-env/reap-dev-env.sh reap <pids>
   ```
   The reaper re-validates each PID is a live paypers dev proc, then TERM → (survivors)
   KILL. It reports any PID it skipped and how many it reaped.

5. **Reap orphaned compose stacks** the scan surfaced — on the user's go-ahead.
   Each stack the scan lists is worktree-gone; `reap-stacks` tears them down
   (`compose down -v` = containers + named volume + network) and, with no NAME arg,
   also sweeps paypers networks with no connected container:
   ```bash
   bash ~/.claude/skills/reap-dev-env/reap-dev-env.sh reap-stacks           # all orphaned stacks
   bash ~/.claude/skills/reap-dev-env/reap-dev-env.sh reap-stacks <name>... # a subset
   ```
   It re-validates each stack is worktree-gone before downing it. Bare dangling volumes
   (incl reseedable dev DBs) are **not** touched here — the cascade hands them to
   `/reap-docker`, which fingerprints before removing.

   For a **live, not-orphaned** stack from the *Running paypers stacks* table (e.g. one
   up 11 days nobody uses), tear it down only on the user's explicit pick — named,
   never blanket:
   ```bash
   bash ~/.claude/skills/reap-dev-env/reap-dev-env.sh reap-stacks --running <name>...
   ```
   `--running` uses each stack's own compose file, `down -v` (containers + volume +
   network), and refuses to run with no NAME. Its host procs are separate — reap those
   with `reap <pids>` from the scan.

6. **Offer the dead-pid lock cleanup** the scan surfaced — `rm` the stale
   `.next/dev/lock`. State the target, don't auto-run.

7. **Report**: what was reaped (procs + stacks + networks), what was kept and why, and
   anything handed to `/reap-docker` or left for the user.

Done when every row the scan printed — procs and orphaned stacks alike — is either
reaped or kept with a stated reason.
