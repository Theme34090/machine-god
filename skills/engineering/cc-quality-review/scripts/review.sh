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
docs_model="${QR_DOCS_MODEL:-claude-haiku-5-5}"
docs_effort="${QR_DOCS_EFFORT:-high}"
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
	docs=null
	[ ! -f "$run/docs-out.md" ] || docs="$(grep -cE '^[^[:space:]]+:[0-9]+ — ' "$run/docs-out.md" || true)"
	jq -nc --arg ts "$(date -u +%FT%TZ)" --arg skill quality-review --arg repo "$repo" \
		--arg branch "$(git rev-parse --abbrev-ref HEAD)" --arg base "$base" \
		--arg from "$(git rev-parse "$from")" --arg head "$(git rev-parse HEAD)" \
		--arg model "$model $effort" --arg spec "$spec" --arg run "$run" \
		--argjson exit "$status" --argjson secs "$((SECONDS - started))" --argjson findings "$findings" --argjson docs "$docs" \
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

is_doc() {
	case "$1" in *.md|*.mdx|*.rst|docs/*|*/docs/*) return 0 ;; esac
	return 1
}

# The docs pass runs when the diff touches a doc, or deletes or renames a path a doc still mentions.
doc_changed=()
doc_new=()
while IFS= read -r f; do
	if is_doc "$f"; then doc_changed+=("$f"); fi
done < <(git diff --name-only "$from" -- ${paths[@]+"${paths[@]}"})
while IFS= read -r f; do
	if is_doc "$f"; then doc_new+=("$f"); fi
done < <(git ls-files --others --exclude-standard --full-name -- ${paths[@]+"${paths[@]}"})

orphans=""
while IFS=$'\t' read -r status old _; do
	case "$status" in D|R*) ;; *) continue ;; esac
	hits="$(git -C "$root" grep -lF -e "$old" -- '*.md' '*.mdx' '*.rst' 'docs/' | tr '\n' ' ' || true)"
	[ -z "$hits" ] || orphans+="- \`$old\` ($status) is still mentioned in: $hits"$'\n'
done < <(git diff --name-status -M "$from" -- ${paths[@]+"${paths[@]}"})

docs_pid=""
if [ ${#doc_changed[@]} -gt 0 ] || [ ${#doc_new[@]} -gt 0 ] || [ -n "$orphans" ]; then
	{
		cat "$skill_dir/references/docs-reviewer-prompt.md"
		printf '\n## Docs Standard\n\n'
		cat "$skill_dir/references/docs-standard.md"
		printf '\n## Doc diff\n\nPaths relative to %s, against %s.\n\n<diff>\n' "$root" "$from"
		[ ${#doc_changed[@]} -eq 0 ] || git -C "$root" diff "$from" -- "${doc_changed[@]}"
		for f in ${doc_new[@]+"${doc_new[@]}"}; do
			(cd "$root" && git diff --no-index -- /dev/null "$f" || true)
		done
		printf '</diff>\n'
		[ -z "$orphans" ] || printf '\n## Orphaned\n\nPaths this diff deleted (D) or renamed (R) that tracked docs still mention:\n\n%s' "$orphans"
	} > "$run/docs-prompt.md"
	(cd "$root" && claude -p --model "$docs_model" --effort "$docs_effort" \
		--tools Read,Grep,Glob --allowedTools Read,Grep,Glob \
		--strict-mcp-config --no-session-persistence --output-format text \
		< "$run/docs-prompt.md" > "$run/docs-out.md" 2> "$run/docs-err.log") &
	docs_pid=$!
fi

codex exec --ephemeral --skip-git-repo-check -C "$dir" \
	-m "$model" -c model_reasoning_effort="$effort" \
	-o "$run/out.md" - < "$run/prompt.md" > "$run/codex.log" 2> "$run/err.log" &
code_pid=$!

code_ok=1
wait "$code_pid" || code_ok=0
docs_ok=1
[ -z "$docs_pid" ] || wait "$docs_pid" || docs_ok=0

# check <pass> <out> <log> <ok>
check() {
	if [ "$4" -eq 0 ]; then
		printf '%s pass failed; see %s\n' "$1" "$3" >&2
		tail -n 20 "$3" >&2
		return 1
	fi
	if [ ! -s "$2" ]; then
		printf '%s pass returned no output; see %s\n' "$1" "$3" >&2
		return 1
	fi
	if ! grep -qE '^No findings\.|^[^[:space:]]+:[0-9]+ — ' "$2"; then
		printf '%s pass output has no findings block; see %s\n' "$1" "$2" >&2
		cat "$2" >&2
		return 1
	fi
}

check code "$run/out.md" "$run/err.log" "$code_ok"
[ -z "$docs_pid" ] || check docs "$run/docs-out.md" "$run/docs-err.log" "$docs_ok"

printf '## Code\n\n'
cat "$run/out.md"
[ -z "$(tail -c1 "$run/out.md")" ] || printf '\n'
printf '\n## Docs\n\n'
if [ -z "$docs_pid" ]; then
	printf 'Skipped: no doc touched or orphaned.\n'
else
	cat "$run/docs-out.md"
	[ -z "$(tail -c1 "$run/docs-out.md")" ] || printf '\n'
fi
