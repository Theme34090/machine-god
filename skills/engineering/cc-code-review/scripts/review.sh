#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf 'usage: review.sh --base <ref> [--spec <file>] [-C <dir>] [path...]\n       review.sh --judge-only <run-dir>\n'
}

base=""
spec=""
dir="$PWD"
judge_only=""
paths=()
while [ $# -gt 0 ]; do
	case "$1" in
		--base) base="$2"; shift 2 ;;
		--spec) spec="$2"; shift 2 ;;
		--judge-only) judge_only="$2"; shift 2 ;;
		-C) dir="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		--) shift; paths+=("$@"); break ;;
		-*) usage >&2; exit 1 ;;
		*) paths+=("$1"); shift ;;
	esac
done

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -n "$spec" ]; then
	[ -f "$spec" ] || { printf 'spec not found: %s\n' "$spec" >&2; exit 1; }
	spec="$(cd "$(dirname "$spec")" && pwd)/$(basename "$spec")"
fi
cd "$dir"

spec_section() {
	[ -f "$1/spec.md" ] || return 0
	printf '\n## Spec\n\nThe diff implements this spec.\n\n<spec>\n'
	cat "$1/spec.md"
	printf '</spec>\n'
}
root="$(git rev-parse --show-toplevel)"

judge() {
	run="$1"
	{
		cat "$skill_dir/references/judge-prompt.md" "$skill_dir/references/severity.md"
		printf '\n## Diff\n\nRelative to %s.\n\n<diff>\n' "$dir"
		cat "$run/diff.patch"
		printf '</diff>\n'
		spec_section "$run"
		printf '\n## Findings\n\n<findings>\n'
		cat "$run/review.md"
		printf '</findings>\n'
	} > "$run/judge-prompt.md"

	printf 'judging...\n' >&2
	if ! pi -p --no-session --mode text --tools read,bash --model zai/glm-5.3:high \
		"$(cat "$run/judge-prompt.md")" > "$run/verdict.md" 2> "$run/judge-err.log"; then
		printf 'pi failed; see %s\n' "$run/judge-err.log" >&2
		tail -n 20 "$run/judge-err.log" >&2
		exit 1
	fi
	if [ ! -s "$run/verdict.md" ]; then
		printf 'pi returned no output; see %s\n' "$run/judge-err.log" >&2
		exit 1
	fi
}

if [ -n "$judge_only" ]; then
	judge "$judge_only"
	cat "$judge_only/verdict.md"
	exit 0
fi

if [ -z "$base" ]; then
	usage >&2
	exit 1
fi
if ! from="$(git merge-base "$base" HEAD 2>/dev/null)"; then
	printf 'cannot resolve --base %s\n' "$base" >&2
	exit 1
fi
head="$(git rev-parse HEAD)"
commits="$(git rev-list --count "$from..HEAD")"
tree="clean working tree"
[ -z "$(git status --porcelain -- ${paths[@]+"${paths[@]}"})" ] || tree="uncommitted changes included"
printf 'Base:   %s (merge-base of %s)\n' "$(git rev-parse --short "$from")" "$base"
printf 'Target: %s (%s), %s commits, %s\n' "$(git rev-parse --short "$head")" "$(git rev-parse --abbrev-ref HEAD)" "$commits" "$tree"
[ "$from" != "$head" ] || printf 'Base equals target: only uncommitted work is in scope.\n'
git log --oneline "$from..HEAD" >&2

diff="$(git diff "$from" -- ${paths[@]+"${paths[@]}"})"
while IFS= read -r f; do
	[ -n "$f" ] || continue
	# `git diff --no-index` exits 1 whenever the files differ.
	diff+="$(printf '\n'; git diff --no-index -- /dev/null "$f" || true)"
done < <(git ls-files --others --exclude-standard -- ${paths[@]+"${paths[@]}"})

if [ -z "$(printf %s "$diff" | tr -d '[:space:]')" ]; then
	printf 'No changes to review.\n'
	exit 0
fi

run="$root/.context/code-review/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run"
printf '%s\n' "$diff" > "$run/diff.patch"
[ -z "$spec" ] || cp "$spec" "$run/spec.md"

{
	cat "$skill_dir/references/reviewer-prompt.md" "$skill_dir/references/severity.md"
	printf '\n## Diff\n\nRelative to %s, against %s (merge-base of %s).\n\n<diff>\n' "$dir" "$from" "$base"
	cat "$run/diff.patch"
	printf '</diff>\n'
	spec_section "$run"
} > "$run/prompt.md"

isolate=(--disable memories --disable plugins --disable apps
	-c memories.use_memories=false -c memories.generate_memories=false
	-c skills.include_instructions=false)
while IFS= read -r server; do
	[ -n "$server" ] && isolate+=(-c "mcp_servers.$server.enabled=false")
done < <(codex mcp list --json | jq -r '.[].name')

printf 'reviewing...\n' >&2
if ! codex exec --ephemeral --skip-git-repo-check -C "$dir" "${isolate[@]}" \
	-m gpt-5.6-sol -c model_reasoning_effort=medium \
	-o "$run/review.md" - < "$run/prompt.md" > "$run/codex.log" 2> "$run/err.log"; then
	printf 'codex failed (%s); see %s\n' "$run/err.log" "$run/codex.log" >&2
	tail -n 20 "$run/err.log" >&2
	exit 1
fi
if [ ! -s "$run/review.md" ]; then
	printf 'codex returned no output; see %s\n' "$run/codex.log" >&2
	exit 1
fi

if [ "$(tr -d '[:space:]' < "$run/review.md")" = "Nofindings." ]; then
	printf 'No findings.\n'
	exit 0
fi

judge "$run"

printf '## Review (%s)\n\n' "$run/review.md"
cat "$run/review.md"
printf '\n## Verdict (%s)\n\n' "$run/verdict.md"
cat "$run/verdict.md"
[ -z "$(tail -c1 "$run/verdict.md")" ] || printf '\n'
