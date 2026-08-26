#!/usr/bin/env bash
# reap-dev-env.sh — find and surgically reap orphaned/stale/old Paypers dev-env
# host procs (next/api/admin + their turbo/tsx/esbuild chain) across EVERY
# worktree layout: canonical, ~/work/paypers/worktrees/*, ~/conductor/workspaces/paypers/*.
#
# The dev-env script's own reaper (scripts/lib/dev-env-common.sh
# reap_orphan_paypers_procs) only greps `paypers/worktrees/` AND only fires
# during a dev-env action — so Conductor-workspace orphans, and orphans on a
# machine where no dev-env command ever runs, pile up unseen. This closes both.
#
# Three subcommands:
#   scan            read-only. enumerate + classify + print table + AUTO_REAP_PIDS.
#   reap PID...     validate each PID is a live paypers dev proc, then TERM->KILL.
#   reap-stacks [NAME...]  tear down orphaned (worktree-gone) paypers compose stacks
#                   via `compose down -v`; with no NAME also sweeps empty paypers
#                   networks. Bare dangling volumes are left to reap-docker.
#   reap-stacks --running NAME...  tear down explicitly-named LIVE (not orphaned)
#                   stacks via `compose down -v`; needs NAME(s), refuses blanket.
#
# SAFETY: scan never kills/removes. reap kills ONLY the explicit PIDs given, each
# re-validated at kill time. reap-stacks tears down ONLY stacks re-validated
# worktree-gone. No pkill, no argv-pattern kill, no -9 before TERM, no blind prune.
set -uo pipefail

DEV_FAMILY='node|pnpm|turbo|tsx|next|esbuild'
OLD_DAYS="${OLD_DAYS:-2}"
OLD_SECS=$(( OLD_DAYS * 86400 ))
CURRENT_ROOT="${CURRENT_ROOT:-}"   # invoking worktree; never auto-reaped
BASE_PORTS=" 3000 8080 3001 "      # tunnel-env singleton fixed ports

# ---- helpers ---------------------------------------------------------------

# strip /apps/<x> or /node_modules/... suffix off a cwd to recover worktree root
root_of_cwd() {
  local c="$1"
  c="${c%/apps/*}"
  c="${c%/node_modules/*}"
  printf '%s' "$c"
}

# [[DD-]HH:]MM:SS -> seconds  (10# guards leading-zero octal)
etime_to_secs() {
  local e="$1" d=0 h=0 rest m s n
  case "$e" in *-*) d="${e%%-*}"; rest="${e#*-}";; *) rest="$e";; esac
  n=$(printf '%s' "$rest" | awk -F: '{print NF}')
  if [ "$n" -eq 3 ]; then h="${rest%%:*}"; rest="${rest#*:}"; fi
  m="${rest%%:*}"; s="${rest#*:}"
  echo $(( 10#${d:-0}*86400 + 10#${h:-0}*3600 + 10#${m:-0}*60 + 10#${s:-0} ))
}

secs_to_human() {
  local s="$1"
  if [ "$s" -ge 86400 ]; then echo "$(( s/86400 ))d$(( (s%86400)/3600 ))h"
  elif [ "$s" -ge 3600 ]; then echo "$(( s/3600 ))h$(( (s%3600)/60 ))m"
  else echo "$(( s/60 ))m"; fi
}

proc_cwd() { lsof -a -p "$1" -d cwd -F n 2>/dev/null | sed -n 's/^n//p' | head -1; }
proc_cmd() { ps -o command= -p "$1" 2>/dev/null; }
proc_age() { etime_to_secs "$(ps -o etime= -p "$1" 2>/dev/null | tr -d ' ')"; }

short_root() { printf '%s' "${1/#$HOME/~}"; }

# is a pid a paypers dev proc? positive evidence only (guards recycled pids)
is_paypers_dev_pid() {
  local pid="$1" cmd cwd comm
  kill -0 "$pid" 2>/dev/null || return 1
  cmd=$(proc_cmd "$pid")
  comm=$(ps -o comm= -p "$pid" 2>/dev/null)
  cwd=$(proc_cwd "$pid")
  case "$cmd$cwd" in *"/paypers"*) ;; *) return 1 ;; esac
  case "$comm" in *next-server*|*node*|*tsx*|*turbo*|*esbuild*|*pnpm*) return 0 ;; esac
  printf '%s' "$cmd" | grep -Eq "/($DEV_FAMILY)" && return 0
  return 1
}

# ---- scan ------------------------------------------------------------------

do_scan() {
  # candidate pids: procs whose command carries a paypers path, PLUS bare
  # next-server workers (comm has no path — only their cwd betrays paypers).
  local cand
  cand=$( { pgrep -f '/paypers/' 2>/dev/null; pgrep -f 'next-server' 2>/dev/null; } | sort -un )

  local tmp; tmp=$(mktemp)
  local pid cwd root exists role age
  for pid in $cand; do
    [ "$pid" = "$$" ] && continue
    cwd=$(proc_cwd "$pid")
    # only paypers procs; a next-server worker outside paypers is not ours
    case "$cwd$(proc_cmd "$pid")" in *"/paypers"*) ;; *) continue ;; esac
    case "$(proc_cmd "$pid")" in *Claude*|*Cursor*|*Code\ Helper*) continue ;; esac

    root=$(root_of_cwd "$cwd")
    # orphan = POSITIVE evidence the worktree is gone (deleted marker or !-d).
    # empty/unreadable cwd -> NOT orphan (never auto-kill on missing evidence).
    exists=1
    case "$cwd" in
      "") exists=unknown ;;
      *"(deleted)"*|*.superset-delete-*) exists=0 ;;
      *) [ -d "$root" ] || exists=0 ;;
    esac
    case "$cwd" in */apps/*) role="${cwd##*/apps/}"; role="${role%%/*}";; *) role=chain;; esac
    age=$(proc_age "$pid")
    printf '%s\t%s\t%s\t%s\t%s\n' "$root" "$pid" "$role" "$exists" "$age" >> "$tmp"
  done

  if [ ! -s "$tmp" ]; then
    echo "No Paypers dev-env host procs found."
    echo "AUTO_REAP_PIDS:"
    # host procs gone, but docker stacks / stale locks can still linger — surface them
    scan_compose_orphans
    scan_running_stacks
    scan_stale_locks_logs "$tmp"
    rm -f "$tmp"
    return 0
  fi

  echo "== Paypers dev-env host procs (old threshold: ${OLD_DAYS}d) =="
  printf '%-7s  %-34s  %-9s  %-9s  %-6s  %s\n' STATE ROOT ROLE PORTS AGE PIDS
  echo "-------------------------------------------------------------------------------------------"

  local roots auto_reap="" root_line pids ports oldest state exists_any role_list
  roots=$(cut -f1 "$tmp" | sort -u)
  while IFS= read -r root; do
    [ -z "$root" ] && continue
    pids=$(awk -F'\t' -v r="$root" '$1==r{print $2}' "$tmp" | sort -un | tr '\n' ' ')
    pids="${pids% }"
    role_list=$(awk -F'\t' -v r="$root" '$1==r{print $3}' "$tmp" | sort -u | tr '\n' ',' | sed 's/,$//')
    oldest=$(awk -F'\t' -v r="$root" '$1==r{print $5}' "$tmp" | sort -rn | head -1)
    exists_any=$(awk -F'\t' -v r="$root" '$1==r{print $4}' "$tmp" | grep -Ev '^1$' | head -1)

    # listening ports actually held by this root's pids (empty => stack not serving)
    ports=$(lsof -Pan -p "$(printf '%s' "$pids" | tr ' ' ',')" -iTCP -sTCP:LISTEN 2>/dev/null \
            | awk 'NR>1{print $9}' | sed 's/.*://' | sort -un | tr '\n' ',' | sed 's/,$//')
    [ -z "$ports" ] && ports="-"

    # classify
    if [ "$exists_any" = "0" ]; then
      state=ORPHAN
      auto_reap="$auto_reap $pids"
    elif [ -n "$CURRENT_ROOT" ] && [ "$root" = "$CURRENT_ROOT" ]; then
      state=CURRENT
    elif printf '%s' ",$ports," | grep -qE ',(3000|8080|3001),'; then
      state=TUNNEL
    elif [ "$ports" = "-" ]; then
      state=STALE
    elif [ "${oldest:-0}" -ge "$OLD_SECS" ]; then
      state=OLD
    else
      state=LIVE
    fi

    printf '%-7s  %-34s  %-9s  %-9s  %-6s  %s\n' \
      "$state" "$(short_root "$root")" "$role_list" "$ports" "$(secs_to_human "${oldest:-0}")" "$pids"
  done <<< "$roots"

  echo ""
  auto_reap=$(printf '%s' "$auto_reap" | tr ' ' '\n' | sed '/^$/d' | sort -un | tr '\n' ' ')
  echo "AUTO_REAP_PIDS: ${auto_reap% }"
  echo ""
  echo "Legend: ORPHAN=worktree gone (auto-reap)  CURRENT=invoking worktree (keep)"
  echo "        TUNNEL=tunnel-env singleton (ask)  STALE=no listener/half-dead  OLD>=${OLD_DAYS}d  LIVE=serving"

  # ---- adjacent leftovers (report only) ----
  scan_compose_orphans
  scan_running_stacks
  scan_stale_locks_logs "$tmp"
  rm -f "$tmp"
}

# echoes "NAME\tROOT" for each worktree-gone paypers-dev/tunnel compose stack
list_compose_orphans() {
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 || return 0
  local json; json=$(docker compose ls --all --format json 2>/dev/null) || return 0
  [ -z "$json" ] && return 0
  python3 - "$json" <<'PY' 2>/dev/null || true
import json,sys,os
try: rows=json.loads(sys.argv[1])
except Exception: sys.exit(0)
for r in rows:
    name=r.get("Name","")
    if not (name.startswith("paypers-dev") or name.startswith("paypers-tunnel")): continue
    cfg=r.get("ConfigFiles","") or ""
    root=os.path.dirname(cfg.split(",")[0]) if cfg else ""
    if root and not os.path.isdir(root):
        print(f"{name}\t{root}")
PY
}

# a real docker-compose.dev.yml to stand in for `compose down` (the stack's own
# worktree file is gone; `down -p` only needs a valid file + the project name)
standin_compose() {
  local f
  for f in "$PWD/docker-compose.dev.yml" \
           "$(git rev-parse --show-toplevel 2>/dev/null)/docker-compose.dev.yml"; do
    [ -f "$f" ] && { echo "$f"; return; }
  done
  find "$HOME/work/paypers" "$HOME/conductor/workspaces/paypers" -maxdepth 2 \
    -name docker-compose.dev.yml 2>/dev/null | head -1
}

# first ConfigFile of a currently-known compose project (live stack still has its file)
stack_configfile() {
  local name="$1" json
  json=$(docker compose ls --all --format json 2>/dev/null) || return 0
  [ -z "$json" ] && return 0
  python3 - "$json" "$name" <<'PY' 2>/dev/null || true
import json,sys
try: rows=json.loads(sys.argv[1])
except Exception: sys.exit(0)
name=sys.argv[2]
for r in rows:
    if r.get("Name")==name:
        print((r.get("ConfigFiles","") or "").split(",")[0]); break
PY
}

scan_compose_orphans() {
  local out; out=$(list_compose_orphans)
  [ -z "$out" ] && return 0
  echo ""
  echo "== Orphaned compose stacks (worktree gone, containers still up) =="
  while IFS=$'\t' read -r name root; do
    [ -z "$name" ] && continue
    echo "  $name  (was: ${root/#$HOME/~})"
  done <<< "$out"
  echo "    reap all: $0 reap-stacks   (or a subset: $0 reap-stacks <name>...)"
}

# report-only: RUNNING paypers compose stacks (live, NOT orphaned) — the "up 11 days
# but forgotten" teardown candidates the orphan scan can't see. Oldest first. These
# are never auto-reaped; kill one explicitly via `reap-stacks --running <name>`.
scan_running_stacks() {
  command -v docker >/dev/null 2>&1 || return 0
  docker info >/dev/null 2>&1 || return 0
  local projs
  projs=$(docker ps --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null \
          | grep -E '^paypers' | sort -u)
  [ -z "$projs" ] && return 0
  local now rows="" proj cids cid cnt oldest st ep ports
  now=$(date +%s)
  while IFS= read -r proj; do
    [ -z "$proj" ] && continue
    cids=$(docker ps -q --filter "label=com.docker.compose.project=$proj")
    cnt=$(printf '%s\n' "$cids" | sed '/^$/d' | wc -l | tr -d ' ')
    oldest=$now
    for cid in $cids; do
      st=$(docker inspect -f '{{.State.StartedAt}}' "$cid" 2>/dev/null)
      st="${st%Z}"; st="${st%.*}"          # strip trailing Z and fractional secs
      ep=$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%S' "$st" +%s 2>/dev/null || echo "$now")
      [ "$ep" -lt "$oldest" ] && oldest=$ep
    done
    ports=$(docker ps --filter "label=com.docker.compose.project=$proj" --format '{{.Ports}}' \
            | grep -oE '0\.0\.0\.0:[0-9]+' | sed 's/0.0.0.0://' | sort -un | tr '\n' ',' | sed 's/,$//')
    [ -z "$ports" ] && ports="-"
    rows="${rows}$(( now - oldest ))	${proj}	${cnt}	${ports}
"
  done <<< "$projs"
  [ -z "$rows" ] && return 0
  echo ""
  echo "== Running paypers stacks (live — NOT orphaned; teardown candidates, oldest first) =="
  printf '  %-26s  %-7s  %-5s  %s\n' STACK AGE CTNRS PORTS
  printf '%s' "$rows" | sort -rn | while IFS=$'\t' read -r secs name cnt ports; do
    [ -z "$name" ] && continue
    printf '  %-26s  %-7s  %-5s  %s\n' "$name" "$(secs_to_human "${secs:-0}")" "$cnt" "$ports"
  done
  echo "    keep unless forgotten. reap one live stack: $0 reap-stacks --running <name>"
}

scan_stale_locks_logs() {
  local tmp="$1" f pid lockroot
  # .next/dev/lock with a dead pid — the FE-collision footgun (a live process
  # scan misses it; you must read the lock, not the process table).
  local live_roots; live_roots=$(cut -f1 "$tmp" | sort -u)
  local hit=""
  while IFS= read -r root; do
    [ -z "$root" ] && continue
    for f in "$root/apps/frontend/.next/dev/lock" "$root/apps/admin/.next/dev/lock"; do
      [ -f "$f" ] || continue
      pid=$(sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "$f" 2>/dev/null | head -1)
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
        hit="$hit  ${f/#$HOME/~} (dead pid $pid)\n"
      fi
    done
  done <<< "$live_roots"
  if [ -n "$hit" ]; then
    echo ""
    echo "== Stale .next/dev/lock (dead pid — blocks FE start) =="
    printf "$hit"
    echo "    reap: rm the lock file(s) above"
  fi
}

# ---- reap ------------------------------------------------------------------

do_reap() {
  local want=("$@") verified=() skipped=() pid
  [ ${#want[@]} -eq 0 ] && { echo "reap: no PIDs given" >&2; return 1; }
  for pid in "${want[@]}"; do
    case "$pid" in *[!0-9]*|"") echo "reap: '$pid' is not a pid — skipped" >&2; continue;; esac
    if is_paypers_dev_pid "$pid"; then verified+=("$pid"); else skipped+=("$pid"); fi
  done
  if [ ${#skipped[@]} -gt 0 ]; then
    echo "Skipped (not a live paypers dev proc): ${skipped[*]}"
  fi
  [ ${#verified[@]} -eq 0 ] && { echo "Nothing to reap."; return 0; }

  echo "Reaping (TERM): ${verified[*]}"
  kill -TERM "${verified[@]}" 2>/dev/null || true
  sleep 2
  local survivors=()
  for pid in "${verified[@]}"; do kill -0 "$pid" 2>/dev/null && survivors+=("$pid"); done
  if [ ${#survivors[@]} -gt 0 ]; then
    echo "Reaping (KILL) survivors: ${survivors[*]}"
    kill -KILL "${survivors[@]}" 2>/dev/null || true
    sleep 1
  fi
  local dead=0
  for pid in "${verified[@]}"; do kill -0 "$pid" 2>/dev/null || dead=$((dead+1)); done
  echo "Reaped ${dead}/${#verified[@]}."
}

# ---- reap-stacks -----------------------------------------------------------
# Tear down orphaned (worktree-gone) paypers compose stacks: `down -v` removes
# each stack's containers + named volume + network. With no NAME arg, also sweep
# paypers networks that have no connected container (orphaned; recreated on next
# `up`). Bare dangling volumes are NOT touched here — /reap-docker fingerprints
# and reaps those.
do_reap_stacks() {
  command -v docker >/dev/null 2>&1 || { echo "reap-stacks: docker not available" >&2; return 1; }
  docker info >/dev/null 2>&1 || { echo "reap-stacks: docker not running" >&2; return 1; }

  # --running: tear down explicitly-named LIVE stacks (bypass orphan check). Needs
  # NAME(s) — refuses a blanket teardown. Uses each stack's own compose file.
  if [ "${1:-}" = "--running" ] || [ "${1:-}" = "--force" ]; then
    shift
    [ "$#" -eq 0 ] && { echo "reap-stacks --running: needs explicit stack NAME(s); refuses blanket teardown" >&2; return 1; }
    local rn=0 name cfg
    for name in "$@"; do
      case "$name" in paypers-dev*|paypers-tunnel*) ;; *) echo "reap-stacks: '$name' not a paypers-dev*/paypers-tunnel* stack — skipped" >&2; continue;; esac
      cfg=$(stack_configfile "$name"); [ -f "$cfg" ] || cfg=$(standin_compose)
      [ -f "$cfg" ] || { echo "reap-stacks: no compose file for $name — skipped" >&2; continue; }
      echo "== down (live): $name =="
      docker compose -p "$name" -f "$cfg" down -v --remove-orphans 2>&1 | grep -Ei 'remov' | sed 's/^/  /'
      rn=$((rn+1))
    done
    echo "--- live stacks down: $rn ---"
    echo "Host procs for these stacks (if any) are separate: reap via '$0 reap <pids>' (see scan)"
    return 0
  fi

  local want=("$@")
  local orphans standin; orphans=$(list_compose_orphans); standin=$(standin_compose)

  local reaped=0 name root
  if [ -z "$orphans" ]; then
    echo "No orphaned compose stacks."
  elif [ -z "$standin" ]; then
    echo "reap-stacks: no docker-compose.dev.yml found for stand-in — cannot down stacks" >&2
    return 1
  else
    while IFS=$'\t' read -r name root; do
      [ -z "$name" ] && continue
      if [ ${#want[@]} -gt 0 ]; then
        local m=0 w; for w in "${want[@]}"; do [ "$w" = "$name" ] && m=1; done
        [ "$m" = 1 ] || continue
      fi
      echo "== down: $name (was ${root/#$HOME/~}) =="
      docker compose -p "$name" -f "$standin" down -v --remove-orphans 2>&1 \
        | grep -Ei 'remov' | sed 's/^/  /'
      reaped=$((reaped+1))
    done <<< "$orphans"
  fi

  # sweep empty paypers networks only on a full (no-NAME) reap — surgical subset stays surgical
  local nets=0 n cnt
  if [ ${#want[@]} -eq 0 ]; then
    for n in $(docker network ls --filter 'name=paypers' --format '{{.Name}}' 2>/dev/null); do
      cnt=$(docker network inspect -f '{{len .Containers}}' "$n" 2>/dev/null)
      [ "${cnt:-0}" = 0 ] && docker network rm "$n" >/dev/null 2>&1 && { echo "  net reaped: $n"; nets=$((nets+1)); }
    done
  fi
  echo "--- stacks down: $reaped, empty paypers networks reaped: $nets ---"
  echo "Bare dangling volumes (incl reseedable dev DBs): reap via /reap-docker"
}

# ---- dispatch --------------------------------------------------------------

case "${1:-}" in
  scan)        shift; do_scan "$@" ;;
  reap)        shift; do_reap "$@" ;;
  reap-stacks) shift; do_reap_stacks "$@" ;;
  *) echo "Usage: $0 <scan | reap PID... | reap-stacks [NAME...] | reap-stacks --running NAME...>" >&2; exit 1 ;;
esac
