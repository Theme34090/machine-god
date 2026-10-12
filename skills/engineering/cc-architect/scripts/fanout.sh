#!/usr/bin/env bash
set -euo pipefail

usage() {
	printf 'usage: fanout.sh prepare <task-file> [-C <dir>]\n       fanout.sh run <run-dir>\n'
}

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sol_model=gpt-6.1-sol
glm_model=zai/glm-5.3:high

prepare() {
	task="$1"
	dir="$2"
	[ -f "$task" ] || { printf 'task not found: %s\n' "$task" >&2; exit 1; }
	cd "$dir"
	root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
	repo="$(basename -s .git "$(git remote get-url origin 2>/dev/null || printf %s "$root")")"
	run="$HOME/.agents/architect/$repo/$(date +%Y%m%d-%H%M%S)-$$"
	mkdir -p "$run"
	printf '%s\n' "$dir" > "$run/dir"
	cp "$task" "$run/task.md"
	{
		cat "$skill_dir/references/runner-prompt.md"
		printf '\n'
		cat "$skill_dir/references/rationale-template.md"
		printf '\n'
		cat "$skill_dir/references/design-red-flags.md"
		printf '\n# Task\n\nRepo: %s\n\n' "$dir"
		cat "$run/task.md"
	} > "$run/prompt.md"
	printf '%s\n' "$run"
}

sol() {
	isolate=(--disable memories --disable plugins --disable apps
		-c memories.use_memories=false -c memories.generate_memories=false
		-c skills.include_instructions=false)
	while IFS= read -r server; do
		[ -n "$server" ] && isolate+=(-c "mcp_servers.$server.enabled=false")
	done < <(codex mcp list --json | jq -r '.[].name')
	codex exec --ephemeral --skip-git-repo-check -C "$dir" "${isolate[@]}" \
		-m "$sol_model" -c model_reasoning_effort=medium \
		-o "$run/sol.md" - < "$run/prompt.md" > "$run/sol.log" 2> "$run/sol-err.log"
}

glm() {
	(cd "$dir" && pi -p --no-session --mode text --tools read,bash --model "$glm_model" \
		"$(cat "$run/prompt.md")") > "$run/glm.md" 2> "$run/glm-err.log"
}

check() {
	if ! wait "$2" || [ ! -s "$run/$1.md" ]; then
		printf '%s seat failed; see %s\n' "$1" "$run/$1-err.log" >&2
		tail -n 20 "$run/$1-err.log" >&2 || true
		return 1
	fi
	printf '%s: %s\n' "$1" "$run/$1.md"
}

run_seats() {
	run="$1"
	[ -f "$run/prompt.md" ] || { printf 'no prompt.md in %s\n' "$run" >&2; exit 1; }
	dir="$(cat "$run/dir")"
	printf 'designing...\n' >&2
	sol & sol_pid=$!
	glm & glm_pid=$!
	failed=0
	check sol "$sol_pid" || failed=$((failed + 1))
	check glm "$glm_pid" || failed=$((failed + 1))
	exit "$failed"
}

case "${1:-}" in
	prepare)
		[ $# -ge 2 ] || { usage >&2; exit 1; }
		task="$2"
		dir="$PWD"
		[ "${3:-}" != "-C" ] || dir="$(cd "$4" && pwd)"
		task="$(cd "$(dirname "$task")" && pwd)/$(basename "$task")"
		prepare "$task" "$dir"
		;;
	run)
		[ $# -eq 2 ] || { usage >&2; exit 1; }
		run_seats "$2"
		;;
	-h|--help) usage ;;
	*) usage >&2; exit 1 ;;
esac
