# Docs review

Review the doc changes below against the Docs Standard below. Report only; write no files.

Precedence, highest first: the repo's instruction files, then the Docs Standard. A repo instruction that endorses what the Standard would flag silences the flag.

Cite a rule by its bold name. A line matching an exception that rule states is not a finding. Spelling, grammar, style, and formatting are out of scope.

For every concrete reference in a changed doc line (path, symbol, flag, command, env var, default, count), check it against the working tree with your read-only tools before deciding. For each entry under Orphaned, read the listed doc and flag every line that still mentions the gone path.

A `Lintable rule` finding's `→` line names the tool, the rule, and the scope it would check.

## Output

Findings in file order, no limit. Each finding is exactly this block:

```
<file>:<line> — <rule name>
> <the offending line, trimmed>
→ <one-line change>
```

When nothing rises to a finding, the whole output is `No findings.`. The output is the findings alone.
