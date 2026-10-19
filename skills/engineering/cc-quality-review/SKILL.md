---
name: cc-quality-review
description: 'YAGNI and smell review of the current diff: flags over-engineering, dead paths, redundant tests, stale comments, and stale or perishable docs; the agent applies the fixes it accepts and logs the rest. Use for /cc-quality-review, "simplify this", "clean up the diff", or after finishing a change, before cc-code-review. For bugs use cc-code-review.'
---

# Quality review

Two passes run in parallel by `scripts/review.sh`. The code pass is gpt-6.1-sol at medium effort through codex, against `references/standards.md`. The docs pass is claude-haiku-5-5 at high effort through `claude -p` with read-only tools, against `references/docs-standard.md`. The docs pass runs only when the diff touches a doc, or deletes or renames a path a tracked doc still mentions. The reviewers report; this agent decides.

## Steps

1. Run `scripts/review.sh` inside the repo, adding `--spec <file>` when a spec or plan the diff implements exists. Default scope is the uncommitted working tree against `HEAD`; `--base <ref>` widens to everything since that ref, paths narrow it. Exit 0 prints a `Run:` line, then a `## Code` and a `## Docs` section. A non-zero exit means a reviewer did not run: show the user stderr and stop here. `No changes to review.`, or `No findings.` under Code with Docs skipped or also `No findings.`, ends the skill with that reported.
2. For each finding, read the cited lines before deciding. Apply it when its fix stays inside the diff's files and adds nothing the standard would flag. Otherwise skip it. A `Spec-covered` finding is neither applied nor skipped: it goes to the user as a decision, with the quoted spec line. A test finding is applied by deleting the test, or by cutting it to what the finding keeps. Skipping one requires naming the specific regression that only this test catches; the skip then goes to the user as a decision, not settled here. "It passes" and "the spec lists it" are not reasons to keep a test. A `Lintable rule` finding goes to the user as a decision with the proposed check, since adding lint config falls outside the diff. A `Perishable fact` with no source of truth to point at is applied by deleting the claim. A `Stale on arrival` finding may edit a doc outside the diff's files.
3. After applying, re-run the tests and checks that cover the changed files. A fix that turns them red is reverted and reported as skipped.
4. Report one ledger covering both passes: every finding by `file:line` as applied, skipped, or spec-covered, one line each with the reason, and the counts matching both reviewers' totals. Save the same ledger to `<run>/outcome.md` for future audits of this skill. The skill is done when the ledger is complete and saved. One review per call; the next loop iteration reviews again.

Artifacts land in `~/.agents/reviews/<repo>/<timestamp>-<pid>-quality-review/` (`prompt.md`, `spec.md` when supplied, `out.md`, `err.log`, `outcome.md`, and `docs-prompt.md`, `docs-out.md`, `docs-err.log` when the docs pass ran), and every run appends one line to `~/.agents/reviews/index.jsonl`. Model and effort are fixed in the script; `QR_MODEL`, `QR_EFFORT`, `QR_DOCS_MODEL`, and `QR_DOCS_EFFORT` override them only when the user asks.
