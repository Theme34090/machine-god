#!/bin/bash
input=$(cat)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'no-repo')
model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
echo "${branch} | tokens: ${pct}% | ${model}"
