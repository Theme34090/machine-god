#!/bin/bash
set -uo pipefail

base=https://raw.githubusercontent.com/Theme34090/machine-god/main
dir="$HOME/.claude"
mkdir -p "$dir/output-styles"
failed=""

fetch() {
  if curl -fsSL --retry 3 "$base/$1" -o "$2.tmp"; then
    mv "$2.tmp" "$2"
  else
    rm -f "$2.tmp"
    return 1
  fi
}

activate_style() {
  local settings="$dir/settings.json"
  if [ ! -s "$settings" ]; then
    echo '{"outputStyle": "Concise (mine)"}' > "$settings"
  else
    jq '.outputStyle = "Concise (mine)"' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
  fi
}

fetch AGENTS.md "$dir/CLAUDE.md" || failed+="- fetch $base/AGENTS.md (global instructions)"$'\n'
if fetch output-styles/concise.md "$dir/output-styles/concise.md"; then
  activate_style || failed+="- set outputStyle in $dir/settings.json"$'\n'
else
  failed+="- fetch $base/output-styles/concise.md (output style)"$'\n'
fi

if [ -n "$failed" ]; then
  cat >> "$dir/CLAUDE.md" <<EOF


# Cloud setup script partly failed

These steps failed:
$failed
Tell the user which steps failed at the start of the session, before doing any work.
Ask whether to proceed without them or fix them now.
EOF
fi
