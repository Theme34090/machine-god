# Quality review

Review the diff below against the standard below. Report only; write no files.

Precedence, highest first: the repo's instruction files loaded with you, the Standard section, the smell baseline. A higher source that endorses what a lower one would flag silences the flag.

The change's scope belongs to its author. Keep the change inside the standard; a different change is out of bounds. Read surrounding files only when a finding depends on what they contain.
Quote a rule whole. A hunk matching an exception that rule states is not a finding.

Formatting, lint, and type errors belong to tooling; leave them out.

## Smell baseline

Each smell is a labelled judgement call. Match it against the diff, read as *what it is → the change*.

- **Mysterious Name**: a name that does not reveal what it does or holds → rename; if no honest name comes, the design is murky.
- **Duplicated Code**: the same logic shape in more than one hunk or file of the change → extract the shape, call it from both.
- **Feature Envy**: a function reaching into another object's data more than its own → move it onto the data it envies.
- **Data Clumps**: the same few fields or params travelling together → one type, passed whole.
- **Primitive Obsession**: a primitive standing in for a domain concept → give the concept its own small type.
- **Repeated Switches**: the same switch or if-cascade on the same type recurring across the change → one map or polymorphism both sites share.
- **Shotgun Surgery**: one logical change forcing scattered edits across many files → gather what changes together.
- **Divergent Change**: one module edited for several unrelated reasons → split so each part changes for one reason.
- **Message Chains**: `a.b().c().d()` navigation the caller depends on → one method on the first object hides the walk.
- **Middle Man**: a function, class, or wrapper that mostly delegates onward → call the real target.
- **Refused Bequest**: an implementer that ignores or overrides most of what it inherits → composition.
- **Spaghetti Branch**: a new conditional or special case inserted into a flow it has nothing to do with → move it behind the abstraction that owns the case.
- **Leaked Feature Logic**: feature-specific logic added to a shared path → isolate it in the feature's own module.
- **Hidden Invariant**: a cast, `any`, `unknown`, optional param, or silent fallback standing in for a boundary the types could state → make the boundary explicit.
- **Oversized File**: the diff pushes a file past 1000 lines → split before growing it.

## Output

At most five findings, fewer preferred, in file order. Each finding is exactly this block:

```
<file>:<line> — <rule: the standard's line quoted, or the smell name>
> <the offending hunk, trimmed>
→ <one-line change>
```

When nothing rises to a finding, the whole output is `No findings.`. The output is the findings alone.
