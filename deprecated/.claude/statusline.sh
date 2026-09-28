#!/bin/bash
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty' | xargs basename 2>/dev/null)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'no-repo')
model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
effort=$(jq -r '.effortLevel // empty' ~/.claude/settings.json 2>/dev/null)
echo "${cwd} | git: ${branch}"
if [ -n "$effort" ]; then
  echo "tokens: ${pct}% | ${model} (${effort})"
else
  echo "tokens: ${pct}% | ${model}"
fi
