---
name: reap-docker
description: Reap generic docker cruft — build cache, unused images, and dangling volumes (fingerprinted before removal). Not dev-env stacks. Personal, user-invoked.
disable-model-invocation: true
---

# reap-docker — reap generic docker cruft

Docker silts up on a machine that builds dev-env / e2e / test stacks all day: build
cache, images no container holds, and **dangling volumes** — postgres data dirs left by
`compose down` (no `-v`), ad-hoc `docker run postgres`, or stacks whose compose file is
already deleted (that deletion is *why* the volume is anonymous + dangling).

Scope is **generic** docker — anything with **no container attached**. A running or
stopped dev-env *stack* is reap-dev-env's job (`reap-stacks` downs it, volume and all);
by the time a `paypers-*_dev_db` volume shows up here it is already **dangling** (its
stack gone), so it is this skill's to reap — flagged `[dev-env DB — reseedable]` as a
reminder it holds seeded test data, in case it is a stopped stack you still want.

## The one rule

Cache and images sweep **blanket** — they regenerate, so `builder prune -af` /
`image prune -af` are safe. **Volumes never do.** A dangling volume may hold the only
copy of real data, so `docker volume prune` — which takes *every* dangling volume at
once, this project or not — is banned. Remove a volume only by **explicit name**, and
only after you have **fingerprinted** its contents.

## Steps

1. **Scan** (read-only):
   ```bash
   bash ~/.claude/skills/reap-docker/reap-docker.sh scan
   ```
   Prints `docker system df`, the **real** sweep-cache reclaim (unreferenced-image
   bytes + build cache — computed by subtracting container-held images, not docker df's
   overstated "Reclaimable"), and a
   dangling-volume table — each volume with its **CreatedAt**, **size**, and a
   **fingerprint** of its contents (`postgresNN` / `empty` / first entries). Paypers dev
   DB volumes are tagged `[DEV-ENV → /reap-dev-env]`. Done when the table is printed;
   `(none)` means no dangling volumes.

2. **Sweep cache + images** (zero risk):
   ```bash
   bash ~/.claude/skills/reap-docker/reap-docker.sh sweep-cache
   ```
   `builder prune -af` + `image prune -af`. Done when it prints the after-`df` and
   build-cache reclaimable is 0. Running stacks keep their images; a stopped stack's
   image just rebuilds on next `up`.

3. **Judge each dangling volume**, then reap the confirmed ones by name. Read the
   fingerprint: an `empty` or fresh `postgresNN` init (size at the image's baseline, ~38 MB
   for pg16) is a throwaway; a larger postgres or non-empty other-content volume may hold
   real data — keep it or ask. Skip anything tagged `[DEV-ENV → /reap-dev-env]`. Present
   the throwaways to the user, reap on confirm:
   ```bash
   bash ~/.claude/skills/reap-docker/reap-docker.sh reap-volumes <vol> <vol> ...
   ```
   Done when every volume in the table is reaped or kept with a stated reason.

4. **Report**: reclaimed space (before/after `df`), what was kept and why.

Done when cache + images are swept and every dangling volume is reaped or kept with a
reason.
