#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf 'usage: review.sh [--base <ref>] [-C <dir>] [path...]\n'
}

base=""
dir="$PWD"
paths=()
while [ $# -gt 0 ]; do
	case "$1" in
		--base) base="$2"; shift 2 ;;
		-C) dir="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		--) shift; paths+=("$@"); break ;;
		-*) usage >&2; exit 1 ;;
		*) paths+=("$1"); shift ;;
	esac
done

model="${QR_MODEL:-gpt-5.6-sol}"
effort="${QR_EFFORT:-low}"
skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$dir"
root="$(git rev-parse --show-toplevel)"

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

run="$root/.context/quality-review/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run"

{
	cat "$skill_dir/references/reviewer-prompt.md"
	printf '\n## Standard\n\n'
	cat ~/.agents/coding-practices.md
	printf '\n## Diff\n\nRelative to %s, against %s.\n\n<diff>\n%s\n</diff>\n' "$dir" "$from" "$diff"
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

cat "$run/out.md"
[ -z "$(tail -c1 "$run/out.md")" ] || printf '\n'
