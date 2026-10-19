# Docs Standard

Prose shipped beside the code: Markdown, READMEs, AGENTS.md and CLAUDE.md, SKILL.md, ADRs, guides. A doc is read long after the diff merges, so every sentence must still hold when nobody edits it for six months.

Each rule names what to flag in the diff and the fix. Flag only what the diff adds or touches, plus docs the diff orphans.

- **Lintable rule.** Prose stating a rule a machine can check: a naming pattern, a file location, a forbidden import or call, a required frontmatter field, a format, an "always" or "never" with a detectable subject → propose the check (tool, rule, scope) and cut the prose to a pointer, or delete it. Exception: a rule whose application needs judgment.
- **Stale on arrival.** A doc line that disagrees with the tree after the diff: it names a path, symbol, flag, command, env var, default, or count that the diff renamed, removed, or changed, or describes behavior the diff changed. Includes untouched docs that still mention a path the diff deleted or renamed → fix the line to match the code.
- **Perishable fact.** A claim tied to a moment: "currently", "now", "new", "recently", "as of", "soon", a relative date, a count ("12 endpoints"), a line number, a version that is not a deliberate pin, a benchmark figure, a current owner or status, a PR or branch link, or an exhaustive list of a set that will grow → state the invariant, point to the source of truth (the file, command, or query that produces the value), or delete it. Exception: a record dated on purpose (changelog, ADR, journal entry, release note) and a version pin with its reason.
