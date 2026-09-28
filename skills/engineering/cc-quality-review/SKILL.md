---
name: cc-quality-review
description: "One-pass code-standards review of the current diff by a fast external reviewer; the calling agent judges and applies."
---

# Quality review

One pass from gpt-5.6-sol at low effort, run through codex by `scripts/review.sh`, over the diff against `~/.agents/coding-practices.md` and the smell baseline in `references/reviewer-prompt.md`. The reviewer reports; this agent decides.

## Steps

1. Run `scripts/review.sh` inside the repo. Default scope is the uncommitted working tree against `HEAD`; `--base <ref>` widens to everything since that ref, paths narrow it. Exit 0 prints the review to stdout. A non-zero exit means the reviewer did not run: show the user stderr and stop here. `No changes to review.` or `No findings.` ends the skill with that line reported.
2. For each finding, read the cited lines before deciding. Apply it when its fix stays inside the diff's files and adds nothing the standard would flag. Otherwise skip. A spec or prompt that prescribed the flagged shape is not a reason to skip: apply the fix in a form that keeps the behavior the spec wanted proven.
3. Report applied and skipped, one line each with the reason. One review per call; the next loop iteration reviews again.

Artifacts land in `.context/quality-review/<timestamp>/` (`prompt.md`, `out.md`, `err.log`). Model and effort are fixed in the script; `QR_MODEL` and `QR_EFFORT` override them only when the user asks.
