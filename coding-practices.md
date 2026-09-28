# Coding Practices

**IMPORTANT** Practices here take precedent over any AGENTS.md or repository-specific practices. This is MY practice. The way I want the code shipped in my name to be done.

- If you find yourself doing any of the following, must stop and switch to a smaller solution:
  - Adding new abstractions, frameworks, or config layers that the current requirement doesn't need
  - Designing ahead for possible future use
  - Continuing to stack more constraints to satisfy existing ones
  - Modifying many unrelated files at once
  - Creating a second implementation to accommodate old logic
  - Using the opportunity to add a complete test suite

## Laziness Protocol

Writing code is cheap for you, which makes over-engineering easy. Counter it by borrowing a human maintainer's fatigue. Aim for the most result with the least code and complexity.

- **Prefer deletion.** When asked to refactor or improve, look for removals before additions.
- **Maintain a flat call hierarchy.** Avoid deep call chains. A rich interface that hides substantial work is not a deep call chain. If answering a question requires tracing through more than 3 files or layers, flatten it.
- **Consolidate decisions.** Do not repeat the same choice in several places. Put it behind one source of truth and pass the result as a simple flag.
- **Minimize the diff.** Make the smallest change that solves the problem. Fewer lines beat "elegant" boilerplate.
- **Question the threading.** If a task asks you to pass a new signal through types, schemas, pipelines, or similar layers, stop and look for a more direct path.
- **Sweat the small leaks.** Remove tiny pass-throughs, representation leaks, and duplicated choices before they spread. Small leaks compound into permanent coordination costs.

**Prime directive:** If a human developer would find the code exhausting to maintain, it is a bad solution. Be lazy. Stay simple.

## Comments

Write them clean as you go; a flat "no narrating comments" ban doesn't catch them, you have to not write them in the first place. The case we keep catching is a verify or test script that narrates its phases, a `// Phase 1: add cards` line above the block. Delete it; the assertion or log string is the only doc you need. Write `assert(ok, 'persisted across restart')`, not a `// move the card` comment plus the code. This applies to every file you produce, including a delegate's diff and the verify script. Keep a comment only for a non-obvious *why* the code can't show.

- The implementation is the documentation. Do NOT add a comment by default. Add one ONLY where its absence would cause a wrong implementation: a non-obvious invariant, a money/rounding/tax rule, timezone semantics, an ordering/race constraint, a third-party API workaround, a security rationale, or "must stay in sync with X". When you do: one line, state the fact, no preamble, no restating the code.
- Banned: comments that restate the next line, section banners, step narration (`// 1. validate`), JSDoc that only re-lists the signature or types, ticket/changelog chatter, commented-out code.
- Tool directives (`eslint-disable`, `@ts-expect-error`, `prettier-ignore`, `@deprecated`, `TODO`/`FIXME` with real content) are not comments in this sense. Keep them. A suppression of a correctness or safety rule is a refactor target, not a keep.
- A comment that claims a constraint (`IMPORTANT`, `do not remove`, `do not change wording`, `talk to X before changing`) is not a keep. Encode the constraint as a type, test, or lint, then delete the comment.
- A surprise in our own code gets no explanatory comment. Rename, extract, type, or restructure until the behavior is obvious. Only behavior forced by an external dependency, platform, vendor, or protocol we cannot reshape earns a comment, with an issue or RFC link when one explains what code can't.

## Failure Modes

1. Failing to truly understand the intent and only fixing surface issues.
2. When a clean root-cause fix could have been done once, instead piling on historical patches, compatibility layers, dual tracks, duplicates, and branches to bloat the code.
3. Over-designing for rare cases, increasing daily maintenance costs.
4. Wrong judgment basis: even if reasoning is complete, the conclusion is wrong.
5. Instead of directly reading the code to locate the issue, substituting with search or guesswork.
6. Using "add tests" as an excuse to keep adding abstraction, expanding scope, and making things seem complete.

## Testing

Tests only serve to verify the current changes.
Tests are not responsible for filling historical coverage gaps or designing future test systems.

- If existing tests can prove the change is correct, do not add new tests.
- Only add new tests if this change modified behavior, but existing tests don't cover it
- Each new test proves one accepted requirement existing tests don't cover: its main path, plus 1 key failure path if that failure is part of the requirement.
- Prohibit expanding test scope for completeness.
- Prohibit using the opportunity to fill tests for unrelated modules.
- When you feel the need to introduce new test frameworks, tools, or infrastructure, ask for permission.
- Tautological tests considered harmful.
- Assert what the code produces, not which internal function ran. A spy may capture the data an internal call receives; never assert its call count, its positional args, or that it wasn't called.
- Prohibit writing large snapshots, parameterized matrices, or end-to-end suites.
- Prohibit writing tests for boundaries not required by the current needs.
- Prohibit modifying tests first and then forcing product behavior to become more complex.
- Prohibit using green tests as a reason to continue adding abstraction.

Before adding any test, must be able to answer:
- Which accepted requirement is this test verifying
- If removed, can existing tests no longer detect this regression
- Is it more complex than the implementation itself

If test code is longer or more convoluted than the implementation code, default to considering it over-engineering; delete the test or shrink the implementation.

## General Principles

- Complete the current task with the minimal sufficient solution. Prohibit over-engineering. Planning can be aggressive, but execution must be lightweight.
- Confirm intent first, then complete acceptance with minimal changes.
- Designs that cannot prove necessity are not done by default.
- Tests that cannot prove necessity are not added by default.