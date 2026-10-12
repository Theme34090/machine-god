#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf 'usage: review.sh [--base <ref>] [--spec <file>] [-C <dir>] [path...]\n'
}

base=""
spec=""
dir="$PWD"
paths=()
while [ $# -gt 0 ]; do
	case "$1" in
		--base) base="$2"; shift 2 ;;
		--spec) spec="$2"; shift 2 ;;
		-C) dir="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		--) shift; paths+=("$@"); break ;;
		-*) usage >&2; exit 1 ;;
		*) paths+=("$1"); shift ;;
	esac
done

model="${QR_MODEL:-gpt-6.1-sol}"
effort="${QR_EFFORT:-medium}"
skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -n "$spec" ]; then
	[ -f "$spec" ] || { printf 'spec not found: %s\n' "$spec" >&2; exit 1; }
	spec="$(cd "$(dirname "$spec")" && pwd)/$(basename "$spec")"
fi

cd "$dir"
root="$(git rev-parse --show-toplevel)"

# One line per run in the shared index, whatever the exit path.
log_run() {
	status=$?
	findings=0
	[ ! -f "$run/out.md" ] || findings="$(grep -cE '^[^[:space:]]+:[0-9]+ — ' "$run/out.md" || true)"
	jq -nc --arg ts "$(date -u +%FT%TZ)" --arg skill quality-review --arg repo "$repo" \
		--arg branch "$(git rev-parse --abbrev-ref HEAD)" --arg base "$base" \
		--arg from "$(git rev-parse "$from")" --arg head "$(git rev-parse HEAD)" \
		--arg model "$model $effort" --arg spec "$spec" --arg run "$run" \
		--argjson exit "$status" --argjson secs "$((SECONDS - started))" --argjson findings "$findings" \
		'$ARGS.named' >> "$HOME/.agents/reviews/index.jsonl"
}

if [ -n "$base" ]; then
	from="$(git merge-base "$base" HEAD)"
else
	from="HEAD"
fi

diff="$(git diff "$from" -- ${paths[@]+"${paths[@]}"})"
while IFS= read -r f; do
	[ -n "$f" ] || continue
	# `git diff --no-index` exits 1 whenever the files differ.
	diff+="$(printf '\n'; git diff --no-index -- /dev/null "$f" || true)"
done < <(git ls-files --others --exclude-standard -- ${paths[@]+"${paths[@]}"})

# bash 3.2 pattern substitution is quadratic; tr keeps this instant on large diffs
if [ -z "$(printf %s "$diff" | tr -d '[:space:]')" ]; then
	printf 'No changes to review.\n'
	exit 0
fi

repo="$(basename -s .git "$(git remote get-url origin 2>/dev/null || printf %s "$root")")"
run="$HOME/.agents/reviews/$repo/$(date +%Y%m%d-%H%M%S)-$$-quality-review"
mkdir -p "$run"
started=$SECONDS
trap log_run EXIT
printf 'Run: %s\n' "$run"
[ -z "$spec" ] || cp "$spec" "$run/spec.md"

{
	cat "$skill_dir/references/reviewer-prompt.md"
	printf '\n## Standard\n\n'
	cat "$skill_dir/references/standards.md"
	printf '\n## Diff\n\nRelative to %s, against %s.\n\n<diff>\n%s\n</diff>\n' "$dir" "$from" "$diff"
	if [ -f "$run/spec.md" ]; then
		printf '\n## Spec\n\nThe diff implements this spec.\n\n<spec>\n'
		cat "$run/spec.md"
		printf '</spec>\n'
	fi
} > "$run/prompt.md"

if ! codex exec --ephemeral --skip-git-repo-check -C "$dir" \
	-m "$model" -c model_reasoning_effort="$effort" \
	-o "$run/out.md" - < "$run/prompt.md" > "$run/codex.log" 2> "$run/err.log"; then
	printf 'codex failed (%s); see %s\n' "$run/err.log" "$run/codex.log" >&2
	tail -n 20 "$run/err.log" >&2
	exit 1
fi

if [ ! -s "$run/out.md" ]; then
	printf 'codex returned no output; see %s\n' "$run/codex.log" >&2
	exit 1
fi

if ! grep -qE '^No findings\.|^[^[:space:]]+:[0-9]+ — ' "$run/out.md"; then
	printf 'reviewer output has no findings block; see %s\n' "$run/out.md" >&2
	cat "$run/out.md" >&2
	exit 1
fi

cat "$run/out.md"
[ -z "$(tail -c1 "$run/out.md")" ] || printf '\n'
