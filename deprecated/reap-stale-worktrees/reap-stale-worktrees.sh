#!/usr/bin/env bash
# reap-stale-worktrees.sh — audit + reap the agent/workflow git worktrees that
# Claude's Agent (isolation:worktree) and Workflow tools leave under
# <repo>/.claude/worktrees/. Those auto-remove ONLY when left unchanged; the
# instant an agent commits, worktree+branch are kept for review and nothing
# reaps them after you merge — so they pile up.
#
# Truth source is GitHub PR state, NOT git ancestry: squash-merge rewrites
# commits, so a shipped branch reads "unmerged" to `git merge-base`. We ask gh.
#
# Three subcommands:
#   scan                    read-only. classify every .claude/worktrees/* into a
#                           tier (A/B/C/D) vs its PR, print table + kill-lists.
#   backup DIR              non-destructive. record every branch tip to
#                           DIR/branch-tips.txt and dump an uncommitted patch for
#                           any dirty worktree. Run before reaping C/D.
#   reap PATH...            unlock->remove --force->branch -D each PATH. Refuses
#                           any PATH outside .claude/worktrees/. Skips dirty/locked
#                           worktrees unless FORCE=1 (protects uncommitted work).
#
# SAFETY: scan never removes. reap acts ONLY on the explicit PATHs given, each
# re-validated to live under .claude/worktrees/ (never the primary, never a
# Conductor city workspace). No pattern matching, no branch -D without a remove.
set -uo pipefail

# ---- repo geometry ---------------------------------------------------------
MAIN_ROOT="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
[ -z "$MAIN_ROOT" ] && { echo "not in a git repo" >&2; exit 1; }
WT_DIR="$MAIN_ROOT/.claude/worktrees"

# emit "PATH<TAB>BRANCH" for every worktree under .claude/worktrees/
list_pairs() {
  git worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{wt=$2} /^branch /{print wt"\t"$2}' \
    | awk -F'\t' -v d="$WT_DIR/" 'index($1,d)==1{sub(/^refs\/heads\//,"",$2); print}'
}

is_locked() { [ -f "$MAIN_ROOT/.git/worktrees/$(basename "$1")/locked" ]; }
dirty_count() { git -C "$1" status --porcelain 2>/dev/null | grep -c .; }
ahead_of_main() { git rev-list --count "origin/main..$1" 2>/dev/null || echo 0; }

# PR state for a branch (bulk map -> gh fallback). Tmpfile map, not an assoc
# array — macOS ships bash 3.2, which has no `declare -A`.
PRMAP="$(mktemp)"; trap 'rm -f "$PRMAP"' EXIT
build_pr_map() {
  gh pr list --state all --limit 500 --json number,state,headRefName 2>/dev/null \
    | python3 -c 'import json,sys
for p in json.load(sys.stdin): print(f"{p["headRefName"]}\t{p["state"]}\t{p["number"]}")' \
    > "$PRMAP" 2>/dev/null || true
}
pr_for() {  # echoes "STATE NUM"; NUM is "-" when no PR. targeted gh on map miss.
  local br="$1" hit r
  hit="$(awk -F'\t' -v b="$br" '$1==b{print $2" "$3; exit}' "$PRMAP" 2>/dev/null)"
  [ -n "$hit" ] && { echo "$hit"; return; }
  r="$(gh pr list --state all --head "$br" --json number,state \
        -q '.[0]|"\(.state) \(.number)"' 2>/dev/null)"
  [ -z "$r" ] && r="NONE -"
  echo "$r"
}

# tier from PR state + dirtiness + lock + ahead-count
classify() {  # args: prstate dirty locked ahead -> echoes A|B|C|D
  local st="$1" dirty="$2" locked="$3" ahead="$4"
  case "$st" in
    MERGED) echo A;;                                   # shipped, residue
    CLOSED) echo B;;                                   # dropped on purpose
    *) # NONE/OPEN: value at risk decides
       if [ "$locked" = 1 ] || [ "$dirty" -gt 0 ]; then echo D    # uncommitted/locked
       elif [ "$ahead" -gt 0 ]; then echo C                       # stray commit
       else echo A; fi;;                               # nothing unique
  esac
}

# ---- scan ------------------------------------------------------------------
cmd_scan() {
  git -C "$MAIN_ROOT" fetch origin main --quiet 2>/dev/null
  build_pr_map
  printf "%-4s %-34s %-14s %-6s %-5s %s\n" TIER WORKTREE PR DIRTY AHEAD BRANCH
  printf -- "---------------------------------------------------------------------------------------------\n"
  local safe="" danger=""
  while IFS=$'\t' read -r wt br; do
    [ -z "$wt" ] && continue
    local name pr st num dirty locked ahead tier
    name="$(basename "$wt")"
    read -r st num <<<"$(pr_for "$br")"; num="${num:-}"
    if [ -n "$num" ] && [ "$num" != "-" ]; then pr="$st #$num"; else pr="$st"; fi
    dirty="$(dirty_count "$wt")"; is_locked "$name" && locked=1 || locked=0
    ahead="$(ahead_of_main "$br")"
    tier="$(classify "$st" "$dirty" "$locked" "$ahead")"
    local dcol="-"
    [ "$dirty" -gt 0 ] && dcol="${dirty}f"
    [ "$locked" = 1 ] && dcol="${dcol}/lk"
    printf "%-4s %-34s %-14s %-6s %-5s %s\n" "$tier" "$name" "$pr" "$dcol" "$ahead" "$br"
    case "$tier" in A|B) safe="$safe $wt";; D) danger="$danger $wt";; esac
  done < <(list_pairs)
  echo
  echo "SAFE_REAP_PATHS:$safe"          # tier A+B — PR-resolved, zero real loss
  echo "DANGER_PATHS:$danger"           # tier D — back up before you touch these
  echo
  echo "Legend: A=merged-PR residue  B=closed-PR (dropped)  C=no-PR stray commit  D=no-PR uncommitted/locked"
}

# ---- backup ----------------------------------------------------------------
cmd_backup() {
  local dir="${1:-}"; [ -z "$dir" ] && { echo "usage: backup DIR" >&2; exit 2; }
  mkdir -p "$dir"
  : > "$dir/branch-tips.txt"
  echo "# branch tips — recover a branch: git branch <name> <sha>" >> "$dir/branch-tips.txt"
  local n=0 p=0
  while IFS=$'\t' read -r wt br; do
    [ -z "$wt" ] && continue
    echo "$(git rev-parse "$br" 2>/dev/null)  $br" >> "$dir/branch-tips.txt"; n=$((n+1))
    if [ "$(dirty_count "$wt")" -gt 0 ]; then
      local f="$dir/$(basename "$wt").uncommitted.patch"
      git -C "$wt" add -A 2>/dev/null
      git -C "$wt" diff --cached --binary > "$f" 2>/dev/null
      git -C "$wt" reset -q 2>/dev/null
      echo "patched $(basename "$wt") -> $(wc -c <"$f") bytes"; p=$((p+1))
    fi
  done < <(list_pairs)
  echo "recorded $n branch tips, $p uncommitted patches -> $dir"
}

# ---- reap ------------------------------------------------------------------
cmd_reap() {
  [ "$#" -eq 0 ] && { echo "usage: reap PATH..." >&2; exit 2; }
  local removed=0 skipped=0
  for wt in "$@"; do
    case "$wt" in */.claude/worktrees/*) :;; *)
      echo "SKIP (outside .claude/worktrees): $wt"; skipped=$((skipped+1)); continue;; esac
    local name br dirty
    name="$(basename "$wt")"; br="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    dirty="$(dirty_count "$wt")"
    if { [ "$dirty" -gt 0 ] || is_locked "$name"; } && [ "${FORCE:-0}" != 1 ]; then
      echo "SKIP (dirty/locked — back up + FORCE=1 to reap): $name"; skipped=$((skipped+1)); continue
    fi
    is_locked "$name" && git worktree unlock "$wt" >/dev/null 2>&1
    if git worktree remove --force "$wt" 2>/dev/null; then
      git -C "$MAIN_ROOT" branch -D "$br" >/dev/null 2>&1 || echo "  (branch kept: $br)"
      echo "REAPED $name"; removed=$((removed+1))
    else
      echo "REMOVE-FAIL $name"; skipped=$((skipped+1))
    fi
  done
  git -C "$MAIN_ROOT" worktree prune 2>/dev/null
  echo "--- reaped $removed, skipped $skipped ---"
}

# ---- dispatch --------------------------------------------------------------
case "${1:-}" in
  scan)   cmd_scan;;
  backup) shift; cmd_backup "$@";;
  reap)   shift; cmd_reap "$@";;
  *) echo "usage: $0 {scan | backup DIR | reap PATH...}" >&2; exit 2;;
esac
