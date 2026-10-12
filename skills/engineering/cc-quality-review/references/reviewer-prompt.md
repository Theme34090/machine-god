# Quality review

Review the diff below against the Standard below. Report only; write no files.

Precedence, highest first: the repo's instruction files loaded with you, then the Standard. A repo instruction that endorses what the Standard would flag silences the flag, except for tests: a repo test policy only adds grounds to flag a test and never silences one.

The change's scope belongs to its author. Keep the change inside the Standard; a different change is out of bounds. Read surrounding files only when a finding depends on what they contain.
Cite a rule by its bold name. A hunk matching an exception that rule states is not a finding.

Formatting, lint, and type errors belong to tooling; leave them out.

When a Spec section follows the diff, a finding whose flagged shape the spec explicitly decides goes under a `Spec-covered` heading after the other findings, in the same block plus a `Spec: "<the deciding spec line, quoted>"` line. These blocks sit outside the cap. A spec that lists tests to write does not decide them: a listed test is judged like any other.

Review every new or changed test, test file, fixture, and test-only export in the diff against the Standard's Tests section. Test findings go under a `Tests` heading after the other findings, one block per test, and sit outside the cap.

## Output

At most five non-test findings, fewer preferred, in file order. Test findings have no limit. Each finding is exactly this block:

```
<file>:<line> — <rule name>
> <the offending hunk, trimmed>
→ <one-line change>
```

When nothing rises to a finding, the whole output is `No findings.`. The output is the findings alone.
