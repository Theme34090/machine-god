#!/usr/bin/env bash
# thin wrapper. shell codex to review code. hide footguns:
#   - stdin trap  -> </dev/null (else codex exec hangs on piped stdin)
#   - dir trust   -> -c projects."<repo>".trust_level=trusted (no prompt)
#   - clean out   -> -o FINAL (read this, not the 9k-line transcript)
# operates on the CURRENT repo state. does NOT mutate git. PR checkout is the caller's job.
set -euo pipefail

EFFORT=low          # -> model_reasoning_effort, passed through verbatim
MODE=normal         # normal (codex `review`) | thermos (thermos skill)
TARGET=main         # main | uncommitted | <branch> | <commit-sha>
CONCERN=""          # extra focus; empty = let codex infer
MODEL="sol"         # alias luna|terra|sol -> gpt-5.6-* ; or full id ; or --model

# accepts --flags OR bare positional tokens (e.g. `run.sh luna low thermos`)
while [ $# -gt 0 ]; do
  case "$1" in
    --effort)  EFFORT="$2"; shift 2;;
    --mode)    MODE="$2"; shift 2;;
    --target)  TARGET="$2"; shift 2;;
    --concern) CONCERN="$2"; shift 2;;
    --model)   MODEL="$2"; shift 2;;
    luna|terra|sol|gpt-*)  MODEL="$1"; shift;;
    low|medium|high|xhigh) EFFORT="$1"; shift;;
    normal|thermos)        MODE="$1"; shift;;
    main|uncommitted)      TARGET="$1"; shift;;
    *) echo "unknown arg: $1 (branch/sha targets need --target)" >&2; exit 2;;
  esac
done

# expand model alias -> full codex model id
case "$MODEL" in
  luna|terra|sol) MODEL="gpt-5.6-${MODEL}";;
esac

command -v codex >/dev/null 2>&1 || { echo "codex CLI not found on PATH" >&2; exit 127; }

REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT="${TMPDIR:-/tmp}/codex-review-${MODE}-$$"
LOG="${OUT}.log"
FINAL="${OUT}.final.md"

# effort + trust the cwd repo so non-interactive exec never blocks on a trust prompt
COMMON=( -c "model_reasoning_effort=${EFFORT}" -c "projects.\"${REPO}\".trust_level=trusted" )
[ -n "$MODEL" ] && COMMON+=( -m "$MODEL" )

if [ "$MODE" = "thermos" ]; then
  case "$TARGET" in
    main|"")     SCOPE='the current branch diff vs origin/main (`git diff origin/main...HEAD`)';;
    uncommitted) SCOPE='the uncommitted working-tree changes (`git status` + `git diff` + `git diff --staged`)';;
    *[!0-9a-f]*) SCOPE="the diff of base \`${TARGET}\` vs HEAD (\`git diff ${TARGET}...HEAD\`)";;
    *)           SCOPE="commit \`${TARGET}\` (\`git show ${TARGET}\`)";;
  esac
  PROMPT="Use the thermos skill (~/.agents/skills/thermos) to run a thermo-nuclear code review of ${SCOPE} in this repo. Follow the thermos workflow: run BOTH passes (bug/security/breakage AND code-quality/maintainability) per the skill's references/, then synthesize. Output findings first, prioritized, with file:line refs and evidence. End with a clear verdict: SAFE TO MERGE / NEEDS CHANGES / BLOCKER."
  [ -n "$CONCERN" ] && PROMPT="${PROMPT}"$'\n\n'"Focus concern: ${CONCERN}"
  codex exec "${COMMON[@]}" -s workspace-write -o "$FINAL" "$PROMPT" </dev/null >"$LOG" 2>&1 || true
else
  TFLAGS=()
  case "$TARGET" in
    main|"")     TFLAGS=( --base main );;
    uncommitted) TFLAGS=( --uncommitted );;
    *[!0-9a-f]*) TFLAGS=( --base "$TARGET" );;
    *)           TFLAGS=( --commit "$TARGET" );;
  esac
  if [ -n "$CONCERN" ]; then
    codex exec review "${COMMON[@]}" "${TFLAGS[@]}" -o "$FINAL" "$CONCERN" </dev/null >"$LOG" 2>&1 || true
  else
    codex exec review "${COMMON[@]}" "${TFLAGS[@]}" -o "$FINAL" </dev/null >"$LOG" 2>&1 || true
  fi
fi

echo "===== CODEX REVIEW (mode=${MODE} effort=${EFFORT} target=${TARGET}) ====="
if [ -s "$FINAL" ]; then
  cat "$FINAL"
else
  echo "(no final message captured — codex may have errored; log tail below)"
  tail -40 "$LOG"
fi
printf '\n----- full transcript: %s -----\n' "$LOG"
