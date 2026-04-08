#!/usr/bin/env python3
"""
PreToolUse hook: blocks package manager install commands.
Exit 2 = block the tool call and surface the message to Claude.
"""

import json
import re
import sys

PATTERNS = [
    # JavaScript / Node
    (r"\bnpm\s+(install|i|ci)\b", "npm"),
    (r"\byarn\s+(install|add)\b", "yarn"),
    # bare yarn: 'yarn' not followed by a word (catches 'yarn', 'yarn --frozen-lockfile', etc.)
    (r"\byarn\s*(?:--[a-z][a-z-]*\s*)*(?:$|&&|;|\|)", "yarn (bare)"),
    (r"\bpnpm\s+(install|i|add)\b", "pnpm"),
    (r"\bbun\s+(install|i|add)\b", "bun"),
    (r"\bnpx\b", "npx"),

    # Python
    (r"\bpip\s+install\b", "pip"),
    (r"\bpip3\s+install\b", "pip3"),
    (r"\bpython\s+-m\s+pip\s+install\b", "python -m pip"),
    (r"\bpython3\s+-m\s+pip\s+install\b", "python3 -m pip"),
    (r"\bpoetry\s+(install|add)\b", "poetry"),
    (r"\bpipenv\s+install\b", "pipenv"),
    (r"\buv\s+pip\s+install\b", "uv pip"),
    (r"\buv\s+(add|sync)\b", "uv"),
    (r"\bconda\s+(install|env\s+create|env\s+update)\b", "conda"),

    # Rust
    (r"\bcargo\s+(install|add|fetch)\b", "cargo"),

    # Go
    (r"\bgo\s+get\b", "go get"),
    (r"\bgo\s+install\b", "go install"),
    (r"\bgo\s+mod\s+(download|tidy)\b", "go mod"),

    # macOS system
    (r"\bbrew\s+(install|upgrade)\b", "brew"),
]

COMPILED = [(re.compile(p, re.IGNORECASE | re.MULTILINE), label) for p, label in PATTERNS]


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    if tool_name != "Bash":
        sys.exit(0)

    command = data.get("tool_input", {}).get("command", "")
    if not command:
        sys.exit(0)

    for pattern, label in COMPILED:
        if pattern.search(command):
            print(
                f"BLOCKED: attempted to run a package install command ({label}).\n"
                "Per user instructions, you MUST ask the user for explicit approval "
                "before installing any packages or dependencies. Do not retry — ask first."
            )
            sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
