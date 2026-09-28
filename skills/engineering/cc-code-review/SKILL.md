---
name: cc-code-review
description: "Two-pass correctness review of a branch: an external reviewer finds defects, an adversarial judge refutes them; the calling agent reports and applies nothing."
---

# Code review

Defects the diff introduces, nothing else. `scripts/review.sh` runs gpt-5.6-sol at medium effort through codex, with skills, memories, plugins, and MCP servers off, over the diff with `references/reviewer-prompt.md`, then glm-5.3 at high thinking through pi with `references/judge-prompt.md` to refute every finding. Both read `references/severity.md`. The reviewer reports, the judge verdicts, this agent tags and presents. No fixes are applied.

## Steps

1. Pin the fixed point: the ref the user named (SHA, branch, tag, `HEAD~5`). If they named none, run `git fetch` and take the open PR's base as `origin/<baseRefName>` from `gh pr view --json baseRefName`; with no PR either, ask the user for the ref and stop.
2. Run `scripts/review.sh --base <fixed-point>` inside the repo, adding `--spec <file>` when the user names the spec or plan the diff implements. The spec lets both passes separate decided behaviour from defects. Scope is merge-base of the fixed point and `HEAD`, through the working tree, untracked files included; paths narrow it. On the fixed point itself that is uncommitted work only. The script fails on a ref that does not resolve. Every run that resolves opens stdout with a `Base:` and a `Target:` line (short SHAs, target branch, commit count, working-tree state), adds `Base equals target` when the merge-base is `HEAD`, and prints the commit list to stderr. Check them against what the user meant and stop on a mismatch. Exit 0 prints the review and the verdict. A non-zero exit means a stage did not run: show the user stderr and stop here. `No changes to review.` or `No findings.` ends the skill with the `Base:` and `Target:` lines and that line reported.
3. Read the verdict. For every `CONFIRMED` critical or high, read the cited lines before tagging it. Tag each confirmed finding by the heuristic below. When the reviewer's fix direction conflicts with what the cited code shows, say so instead of passing it through.
4. Report, in this order, and then stop:
   - the `Base:` and `Target:` lines, verbatim, plus `Base equals target` when present;
   - confirmed findings, numbered, ordered by severity, each with its tag and the one-line reason;
   - unverifiable findings, unnumbered, each with why the code could not settle it and what would, tagged `your call`;
   - `COVERED` spec-covered items, one line each with the quoted spec line; a `not covered:` item is reported with the regular findings under its verdict;
   - one line each for refuted findings (with the disproving reason), cosmetic lines, pre-existing items, and anything under `Judge noticed`.

## Fix-or-not heuristic

- **fix**: critical or high; or medium whose fix stays inside the diff's files.
- **skip**: the fix touches shared code outside the diff, or the trigger needs a state the author would not test for.
- **your call**: anything else, with the tradeoff stated in one line.

Artifacts land in `.context/code-review/<timestamp>/` (`prompt.md`, `diff.patch`, `spec.md` when supplied, `review.md`, `judge-prompt.md`, `verdict.md`, `err.log`, `judge-err.log`). `scripts/review.sh --judge-only <that dir>` re-runs the judge on a saved review.
