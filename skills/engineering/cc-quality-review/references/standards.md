# Coding Standards

The standard for code shipped in my name. I maintain every line, so a change is sized to what a tired maintainer would still accept.

Each rule names what to flag in the diff and the fix. Flag only what the diff adds or touches.

## Size (YAGNI)

A finding whose fix adds a type, layer, module, or endpoint must show that it deletes more than it adds; otherwise drop it.

- **Unneeded structure.** An abstraction, config option, layer, endpoint, or type the current requirement does not use → inline it or delete it.
- **Speculative design.** Handling for a case the requirement does not name: a guard, validator, fallback, option, or extension point for a future caller → delete it.
- **Middle Man.** A wrapper with one caller, an adapter with one implementation, a layer that repeats the methods and arguments of the one below → call the real target.
- **Shotgun Surgery.** A new value passed through three or more types, schemas, or call layers to reach the one place that uses it, or one logical change scattered across many files → compute or read it where it is used.
- **Repeated decision.** The same choice, logic shape, or switch on the same type made in more than one place → decide once, pass the result.
- **Misplaced logic.** A feature-specific condition or special case inserted into a shared path or an unrelated flow → move it to the module that owns the case.
- **Dual path.** A second implementation, compatibility shim, or legacy branch kept alive beside the new one → migrate the callers and delete the old path in the same change.
- **Symptom patch.** A guard, retry, or special case that silences a failure without fixing its cause → fix the cause, delete the patch.
- **Unrelated edits.** Changes to files or behavior outside the task → revert them.
- **Oversized File.** The diff pushes a file past 1000 lines → split before growing it.

## Boundaries and types

- **Hidden Invariant.** A cast, `any`, non-null assertion, optional param, or silent fallback (`??`, `||`, a default value) standing in for a rule the code should state → make it explicit: parse at the boundary, or handle the case. Check what the fallback does when its input is empty, deleted, or arrives late.
- **Internal re-validation.** A null check, parse, or validation on data that already passed a system boundary → delete it; validate once at the boundary.
- **Contradictory state.** Optional fields or booleans that admit meaningless combinations (`done: true` with no `doneAt`) → derive the flag from one source or use a discriminated union. Strengthen a type only where a runtime check would otherwise exist.
- **Mysterious Name.** A name that does not reveal what it does or holds → rename it.

## Comments

The code is the documentation. The default is no comment.

- **Flag:** a comment that restates the next line, a section banner, step narration (`// 1. validate`, `// Phase 1: add cards`), JSDoc that only repeats the signature, ticket or changelog chatter, commented-out code → delete it. In a test or verify script, the assertion message carries the meaning: `assert(ok, 'persisted across restart')`.
- **Flag:** a comment that explains a surprise in our own code → rename, extract, or restructure until the code is obvious, then delete the comment.
- **Flag:** a comment that claims a constraint (`IMPORTANT`, `do not remove`, `keep in sync`) → encode it as a type, test, or lint, then delete the comment.
- **Keep:** one line stating a fact the code cannot show and whose absence would cause a wrong change: a money, rounding, or tax rule, timezone semantics, an ordering or race constraint, a third-party or platform workaround (with an issue link when one exists), or a security reason.
- **Keep:** tool directives (`eslint-disable`, `@ts-expect-error`, `prettier-ignore`, `@deprecated`, `TODO`/`FIXME` with real content). A directive that suppresses a correctness or safety rule is a refactor finding, not a keep.

## Tests

Every new or changed test is presumed deletable. The test carries the burden of proof, not the reviewer.

Flag a test unless the diff or spec shows all three:

1. the accepted requirement this change modified that the test proves,
2. that nothing else (an existing test, a type, a lint rule, or the repo's verification recipe) would catch its regression,
3. that it asserts one produced value against a literal.

Grounds, each alone a finding:

- **Redundant test.** Another test, type, lint rule, or verification recipe covers the same regression → delete it.
- **Scope creep.** Tests unchanged behavior, a boundary the requirement does not name, or another module → delete it.
- **Pinned detail.** Asserts error or log wording, a field-by-field copy, a whole output object, a timestamp, or a snapshot → delete it, or keep one produced value.
- **Implementation assertion.** A spy's call count, its positional args, or that it was not called → delete it.
- **Tautology.** The expected value is re-derived with the code under test, or a mock's own return is asserted → delete it.
- **Stubbed around pure logic.** Network, DB, or filesystem stubbed to reach logic in a pure function → delete it, or call the function directly.
- **Failure path not in the requirement.** Tests a failure the requirement does not name → delete it.
- **Live or end-to-end test.** Hits a real service, or repeats what a verification recipe proves → delete it.
- **Test-only seam.** An export, parameter, or hook added to production code only so a test can reach it → delete both.
- **Test heavier than code.** New test lines exceed a third of the new code lines, or one test is longer than the function it tests → flag every test in the file.
- **New infrastructure.** A new test framework, helper library, or fixture system → delete it and ask the user.
