#!/usr/bin/env bash
# thin wrapper. shell codex to run a THERMOS review. hide footguns:
#   - stdin trap  -> </dev/null (else codex exec hangs on piped stdin)
#   - dir trust   -> -c projects."<repo>".trust_level=trusted (no prompt)
#   - clean out   -> -o FINAL (read this, not the 9k-line transcript)
#   - session     -> session id captured from the log so re-reviews resume the
#                    same codex thread (it already knows the findings)
# operates on the CURRENT repo state. does NOT mutate git. PR checkout is the caller's job.
set -euo pipefail

EFFORT=low          # -> model_reasoning_effort, passed through verbatim
TARGET=main         # main | uncommitted | <branch> | <commit-sha>
CONCERN=""          # extra focus; empty = let codex infer
MODEL="sol"         # alias luna|terra|sol -> gpt-5.6-* ; or full id ; or --model
RESUME=0            # 1 = re-review inside the previous codex session
FRESH=0             # 1 = force a new session even for a re-review

# accepts --flags OR bare positional tokens (e.g. `run.sh luna low resume`)
while [ $# -gt 0 ]; do
  case "$1" in
    --effort)  EFFORT="$2"; shift 2;;
    --target)  TARGET="$2"; shift 2;;
    --concern) CONCERN="$2"; shift 2;;
    --model)   MODEL="$2"; shift 2;;
    --resume|resume|re-review) RESUME=1; shift;;
    --fresh|fresh)             FRESH=1; shift;;
    luna|terra|sol|gpt-*)  MODEL="$1"; shift;;
    low|medium|high|xhigh) EFFORT="$1"; shift;;
    main|uncommitted)      TARGET="$1"; shift;;
    # agent-layer modes — handled by the skill, not the runner. tolerated so a
    # raw `/codex-review fix` doesn't blow up if passed through verbatim.
    thermos|fix|loop-fix|loopfix) shift;;
    *) echo "unknown arg: $1 (branch/sha targets need --target)" >&2; exit 2;;
  esac
done

[ "$FRESH" = 1 ] && RESUME=0

# expand model alias -> full codex model id
case "$MODEL" in
  luna|terra|sol) MODEL="gpt-5.6-${MODEL}";;
esac

command -v codex >/dev/null 2>&1 || { echo "codex CLI not found on PATH" >&2; exit 127; }

REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
OUT="${TMPDIR:-/tmp}/codex-review-$$"
LOG="${OUT}.log"
FINAL="${OUT}.final.md"

# session id is keyed by branch: a re-review of the same branch is the same
# conversation, a different branch is a different review.
# prefer the conductor workspace's .context/ (already gitignored, and per-workspace
# so it dies with the workspace). only used when it already exists — never create
# an untracked dir in a repo that isn't a conductor workspace.
if [ -n "${CODEX_REVIEW_STATE_DIR:-}" ]; then
  STATE_DIR="$CODEX_REVIEW_STATE_DIR"; KEY="${REPO}#${BRANCH}"
elif [ -d "${REPO}/.context" ]; then
  STATE_DIR="${REPO}/.context/codex-review"; KEY="$BRANCH"   # dir is already repo-scoped
else
  STATE_DIR="$HOME/.claude/state/codex-review"; KEY="${REPO}#${BRANCH}"
fi
SESSION_FILE="${STATE_DIR}/$(printf '%s' "$KEY" | tr -c 'A-Za-z0-9._-' '_').session"
mkdir -p "$STATE_DIR"

case "$TARGET" in
  main|"")     SCOPE='the current branch diff vs origin/main (`git diff origin/main...HEAD`)';;
  uncommitted) SCOPE='the uncommitted working-tree changes (`git status` + `git diff` + `git diff --staged`)';;
  *[!0-9a-f]*) SCOPE="the diff of base \`${TARGET}\` vs HEAD (\`git diff ${TARGET}...HEAD\`)";;
  *)           SCOPE="commit \`${TARGET}\` (\`git show ${TARGET}\`)";;
esac

# machine-readable tail so a fix loop can decide whether to iterate again
TAIL_CONTRACT='End your output with exactly two lines, nothing after them:
VERDICT: <SAFE TO MERGE|NEEDS CHANGES|BLOCKER>
REMAINING MUST-FIX: <integer count of findings that still block merge>'

FIRST_PROMPT="Use the thermos skill (~/.agents/skills/thermos) to run a thermo-nuclear code review of ${SCOPE} in this repo. Follow the thermos workflow: run BOTH passes (bug/security/breakage AND code-quality/maintainability) per the skill's references/, then synthesize. Output findings first, prioritized, with file:line refs and evidence.

${TAIL_CONTRACT}"

RESUME_PROMPT="Fixes have been applied to the working tree since your last review. Re-review ${SCOPE}.

For EVERY finding you raised previously, state FIXED / PARTIAL / NOT FIXED with file:line evidence from the current code — do not trust a claim that it was fixed, read it. Then look for NEW issues the fixes introduced (regressions, half-applied edits, broken callers). Do not re-litigate findings you already accepted as resolved.

${TAIL_CONTRACT}"

[ -n "$CONCERN" ] && { FIRST_PROMPT="${FIRST_PROMPT}"$'\n\n'"Focus concern: ${CONCERN}"; RESUME_PROMPT="${RESUME_PROMPT}"$'\n\n'"Focus concern: ${CONCERN}"; }

# effort + trust the cwd repo so non-interactive exec never blocks on a trust prompt.
# sandbox goes through -c, not -s: `codex exec resume` rejects -s (exits 2 on
# "unexpected argument '-s'"), and -c works on both subcommands.
COMMON=( -c "model_reasoning_effort=${EFFORT}" -c "projects.\"${REPO}\".trust_level=trusted" -c 'sandbox_mode="workspace-write"' )
[ -n "$MODEL" ] && COMMON+=( -m "$MODEL" )

SID=""
[ -s "$SESSION_FILE" ] && SID="$(cat "$SESSION_FILE")"

if [ "$RESUME" = 1 ] && [ -n "$SID" ]; then
  KIND="resume ${SID}"
  codex exec resume "${COMMON[@]}" -o "$FINAL" "$SID" "$RESUME_PROMPT" </dev/null >"$LOG" 2>&1 || true
elif [ "$RESUME" = 1 ]; then
  # asked to resume but nothing recorded — run the full review instead of silently
  # re-reviewing a session that doesn't exist
  KIND="fresh (no recorded session for ${BRANCH})"
  codex exec "${COMMON[@]}" -o "$FINAL" "$FIRST_PROMPT" </dev/null >"$LOG" 2>&1 || true
else
  KIND="fresh"
  codex exec "${COMMON[@]}" -o "$FINAL" "$FIRST_PROMPT" </dev/null >"$LOG" 2>&1 || true
fi

NEW_SID="$(grep -m1 -oE 'session id: [0-9a-f-]{36}' "$LOG" | awk '{print $3}' || true)"
[ -n "$NEW_SID" ] && printf '%s' "$NEW_SID" >"$SESSION_FILE"

echo "===== CODEX THERMOS REVIEW (effort=${EFFORT} target=${TARGET} session=${KIND}) ====="
if [ -s "$FINAL" ]; then
  cat "$FINAL"
else
  echo "(no final message captured — codex may have errored; log tail below)"
  tail -40 "$LOG"
fi
printf '\n----- full transcript: %s -----\n' "$LOG"
