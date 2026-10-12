---
name: cc-quality-review
description: 'YAGNI and smell review of the current diff: flags over-engineering, dead paths, redundant tests, and stale comments; the agent applies the fixes it accepts and logs the rest. Use for /cc-quality-review, "simplify this", "clean up the diff", or after finishing a change, before cc-code-review. For bugs use cc-code-review.'
---

# Quality review

One pass from gpt-6.1-sol at medium effort, run through codex by `scripts/review.sh`, over the diff against `references/standards.md`. The reviewer reports; this agent decides.

## Steps

1. Run `scripts/review.sh` inside the repo, adding `--spec <file>` when a spec or plan the diff implements exists. Default scope is the uncommitted working tree against `HEAD`; `--base <ref>` widens to everything since that ref, paths narrow it. Exit 0 prints a `Run:` line, the artifact directory, then the review. A non-zero exit means the reviewer did not run: show the user stderr and stop here. `No changes to review.` or `No findings.` ends the skill with that line reported.
2. For each finding, read the cited lines before deciding. Apply it when its fix stays inside the diff's files and adds nothing the standard would flag. Otherwise skip it. A `Spec-covered` finding is neither applied nor skipped: it goes to the user as a decision, with the quoted spec line. A test finding is applied by deleting the test, or by cutting it to what the finding keeps. Skipping one requires naming the specific regression that only this test catches; the skip then goes to the user as a decision, not settled here. "It passes" and "the spec lists it" are not reasons to keep a test.
3. After applying, re-run the tests and checks that cover the changed files. A fix that turns them red is reverted and reported as skipped.
4. Report a ledger: every finding by `file:line` as applied, skipped, or spec-covered, one line each with the reason, and the counts matching the reviewer's total. Save the same ledger to `<run>/outcome.md` for future audits of this skill. The skill is done when the ledger is complete and saved. One review per call; the next loop iteration reviews again.

Artifacts land in `~/.agents/reviews/<repo>/<timestamp>-<pid>-quality-review/` (`prompt.md`, `spec.md` when supplied, `out.md`, `err.log`, `outcome.md`), and every run appends one line to `~/.agents/reviews/index.jsonl`. Model and effort are fixed in the script; `QR_MODEL` and `QR_EFFORT` override them only when the user asks.
