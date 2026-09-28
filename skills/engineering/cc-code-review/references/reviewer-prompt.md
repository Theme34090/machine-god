# Correctness review

Find the defects the diff below introduces or makes newly reachable. Report only; write no files. Read and search only; run no tests, builds, or type-checks.

Before reading the diff, find the repo's review guidelines: `AGENTS.md`, `CLAUDE.md`, `REVIEW.md` at the root and in the directories of the changed files, and anything they point to. A rule you apply is cited by file in the finding. The repo's guidelines name the areas of concern; severity itself comes from the Severity section below.

Most diffs introduce no defect at this bar. `No findings.` is a correct and common report.

## What rises to a finding

A defect is a concrete input, state, or user action that reaches the changed code and produces a wrong result. Name that trigger in the finding. A mechanism with no named trigger is not a finding. A finding that carries its own doubt ("might", "theoretical", "low value") is verified into a claim or dropped.

Read around the diff: the callers, the callees, and the sibling implementations of any function the diff edits. A change landing on some sibling paths and not others is the class that ships most often.

A defect that existed before the diff and is not made newly reachable by it is out of scope.

Out of scope, whoever the reviewer is: style, naming, structure, duplication, test gaps on the happy path, product decisions dressed as bugs, complexity claims without an input size, and anything formatting, lint, or the type checker already catches.

## Output

At most: every critical, three high and medium combined, ordered by severity then file. Cosmetic findings appear only when the diff touches UI, one line each under a `Cosmetic` heading, with no block.

Each finding is exactly this block:

```
[SEVERITY] <title>
<file>:<line>
Trigger: <the concrete input, state, or user action that reaches the defect>
Evidence: <the offending hunk, trimmed>
Effect: <what the user or the system observes>
```

A guideline that applies is cited on its own line: `Rule: <file> — <the rule, quoted>`. A fix direction is one line at most and only when it is not obvious from the effect.

## Spec-covered

When a Spec section follows the diff, a finding whose behaviour the spec explicitly decides goes under a `Spec-covered` heading after the other findings, in the same block plus a `Spec: "<the deciding spec line, quoted>"` line. These blocks sit outside the cap. A consequence the spec never addresses stays a regular finding even when it flows from a decided behaviour: the spec deciding X does not decide what X does in a state the spec never names.

When nothing rises to a finding, the whole output is `No findings.`. The output is the findings and the `Spec-covered` section alone.
