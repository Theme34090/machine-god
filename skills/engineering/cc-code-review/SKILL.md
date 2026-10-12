---
name: cc-code-review
description: 'Bug review of a branch before merge: finds defects the diff introduces and has a second model refute each; reports only, applies nothing. Slow (5–15 min). Use for /cc-code-review, "review for bugs", "safe to merge?", or before opening a PR. For over-engineering and smells use cc-quality-review.'
---

# Code review

Defects the diff introduces, nothing else. `scripts/review.sh` runs gpt-6.1-sol at medium effort through codex, with skills, memories, plugins, and MCP servers off, over the diff with `references/reviewer-prompt.md`, then glm-5.3 at high thinking through pi with `references/judge-prompt.md` to refute every finding. Both read `references/severity.md`. The reviewer reports, the judge verdicts, this agent tags and presents. No fixes are applied. A run takes 5 to 15 minutes, mostly in the judge; keeping it alive past a command timeout is the caller's job.

## Steps

1. Pin the fixed point: the ref the user named (SHA, branch, tag, `HEAD~5`). If they named none, run `git fetch` and take the open PR's base as `origin/<baseRefName>` from `gh pr view --json baseRefName`; with no PR either, ask the user for the ref and stop.
2. Run `scripts/review.sh --base <fixed-point>` inside the repo, adding `--spec <file>` when the user names the spec or plan the diff implements. The spec lets both passes separate decided behaviour from defects. Scope is merge-base of the fixed point and `HEAD`, through the working tree, untracked files included; paths narrow it. On the fixed point itself that is uncommitted work only. The script fails on a ref that does not resolve. Every run that resolves opens stdout with a `Base:` and a `Target:` line (short SHAs, target branch, commit count, working-tree state), adds `Base equals target` when the merge-base is `HEAD`, and prints the commit list to stderr. A run with changes to review then prints a `Run:` line, its artifact directory. Check them against what the user meant and stop on a mismatch. Exit 0 prints the review and the verdict. Exit 3 means the judge failed after the review printed: show the user stderr, then report the reviewer's findings as unjudged, each tagged `your call`; `--judge-only` re-runs the judge later. Any other non-zero exit means a stage did not run: show the user stderr and stop here. `No changes to review.` or `No findings.` ends the skill with the `Base:` and `Target:` lines and that line reported. `No findings.` is the reviewer's word alone, the judge never saw it: report it as one reviewer pass, not as merge readiness.
3. Read the verdict. For every `CONFIRMED` critical or high, read the cited lines before tagging it. Tag each confirmed finding by the heuristic below. When the reviewer's fix direction conflicts with what the cited code shows, say so instead of passing it through.
4. Save to `<run>/outcome.md` one line per finding, confirmed, unverifiable, `COVERED`, and `Judge noticed` alike: `file:line`, verdict, tag, and the one-line reason. Future audits of this skill read it.
5. Report, in this order, and then stop:
   - the `Base:` and `Target:` lines, verbatim, plus `Base equals target` when present;
   - confirmed findings, numbered, ordered by severity, each with its tag and the one-line reason;
   - unverifiable findings, unnumbered, each with why the code could not settle it and what would, tagged `your call`;
   - `COVERED` spec-covered items, one line each with the quoted spec line; a `not covered:` item is reported with the regular findings under its verdict;
   - `Judge noticed` items, unnumbered and marked unverified, each tagged by the heuristic below;
   - one line each for refuted findings (with the disproving reason), cosmetic lines, and pre-existing items.

## Fix-or-not heuristic

- **fix**: critical or high; or medium whose fix stays inside the diff's files and adds no endpoint, field, or other API surface.
- **skip**: the fix touches shared code outside the diff, or the trigger needs a state the author would not test for.
- **your call**: anything else, with the tradeoff stated in one line.

Artifacts land in `~/.agents/reviews/<repo>/<timestamp>-<pid>-code-review/` (`prompt.md`, `diff.patch`, `spec.md` when supplied, `review.md`, `judge-prompt.md`, `verdict.md`, `err.log`, `judge-err.log`, `outcome.md`), and every run appends one line to `~/.agents/reviews/index.jsonl`. `scripts/review.sh --judge-only <that dir>` re-runs the judge on a saved review.
