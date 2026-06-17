# Review Assist

Triage issues from code review from other agents and put them into buckets to help user take next step.

## Severity guidance

- 🔴 must-fix: can't merge if not addressed. such as broken functionality, severe edge case, system invariant broken, things that could lead to system failure
- 🟡 should-fix: can allow to merge but highly recommend to address before. such as edge case that doesn't cause system disruption, cosmetic issues, functioning but degraded user experience, would lead to technical debt
- 🔵 nitpick: recommend to address but fine to leave it. such as code duplication, stale/wrong comments, best practices violation

## Delivery

Write full writeup file to tmp dir and present short summary to user

### General guideline

- use caveman dialect
- sort by must-fix > should-fix > nitpick
- renumber issues sequentially 1..N AFTER sorting by severity. Do not preserve upstream IDs from source review (e.g., /code-review JSON array order).

### Writeup

- for must-fixes, give additional context around the issue
	- which change cause the issue
	- what if not fix
	- failure scenario
	- proposed fix shape and why

### Short summary for human

- use emoji 🔴, 🟡, 🔵
- for each issue, do 1-liner summary of the issue
- actionable next step
	- surface what requires human attention. e.g need product input or decision on fix shape
	- what could be auto apply