---
name: cc-principles
description: "Engineering principles, non-negotiables, reply rules, and comment rules for rigorous work. Use for /cc-principles, at the start of any non-trivial coding task, or when the user asks to work by the principles."
---

# Principles

## Non-negotiables

**Start every multi-step task with a todolist whose first item is to read the Principles section below in full.** The principles ground every trigger here. In your reply, name each principle that shaped a decision and the specific choice it changed. A citation with no decision behind it means you skipped its leaf file; it must trace to a real choice the leaf's rule drove.

Remaining triggers:

- Nontrivial change, architecture decision, or "are we sure?" → the **cc-how** skill.
- About to ask the user on a "which approach", "how should I", or "what should this do" fork → classify it before you ask. If the answer is a fact you could observe by running something (behavior, timing, layout, output, perf, even whether an eval separates), it is not the human's to answer. Sketch it as a throwaway prototype (the **cc-prototype** skill), observe the result, and let the result decide. If the task is a read-only investigation whose deliverable is a cited answer, stay in it and answer from the evidence rather than building a sketch. Reserve the question for a genuine product or preference call no experiment can settle. The ask is the slow path. A throwaway probe usually answers faster, and it hands the human a result to react to instead of a decision to make.
- Any code → name the data shape first, and choose its organizing structure per the **model-the-domain** principle.
- Code crossing a function boundary → settle the caller's usage first, then the types, signatures, and module shape, before implementing. Design it twice: at least two structurally distinct candidates before committing, not a second flavor of the first shape.
- Any prose surface → the **cc-unslop** skill. Your reply is a prose surface; write it per **Writing the reply**. Agent-facing prose also follows the **cc-writing-for-agents** skill.
- Docs, RFCs, readmes, PR descriptions, or commit messages → the **cc-technical-writing** skill.
- Before commit → remove narrating comments, unsupported guards, dead compatibility paths, and unrelated edits from the diff.
- Before review → the **cc-no-comments** skill.
- Broken skill mid-task → fix it in its own PR. Don't block. Don't silently work around it.
- Long, autonomous, or multi-phase work, or any task the user steps away from to review later ("going to bed", "trust it when i'm back", "run until done") → a decision trail via the **cc-show-me-your-work** skill. Commit it when stakes need an auditable record; keep it local otherwise.

## Principles

Read the leaf file in full for any principle you apply. Each entry names when it applies.

**Core**

- **Laziness Protocol** (`references/laziness-protocol.md`). Refactoring, sizing a diff, or tempted to add abstractions, layers, or signal threading. Bias to deletion and the smallest change that solves the problem.
- **Foundational Thinking** (`references/foundational-thinking.md`). Before writing logic: core types and data structures, scaffold-vs-feature sequencing, what concurrent actors share.
- **Redesign from First Principles** (`references/redesign-from-first-principles.md`). Integrating a new requirement into an existing design. Redesign as if it had been foundational from day one.
- **Subtract Before You Add** (`references/subtract-before-you-add.md`). Sequencing an addition, refactor, or rewrite. Remove dead weight first, then build on the simpler base.
- **Minimize Reader Load** (`references/minimize-reader-load.md`). Reviewing or shaping code that's hard to trace. Count layers and hidden state, collapse one-caller wrappers, shrink mutable scope.
- **Outcome-Oriented Execution** (`references/outcome-oriented-execution.md`). Planned rewrites and migrations with explicit phase boundaries. Converge on the target architecture, don't preserve throwaway compatibility states.
- **Experience First** (`references/experience-first.md`). Product, UX, or feature-scope tradeoffs. Choose user delight over implementation convenience.
- **Exhaust the Design Space** (`references/exhaust-the-design-space.md`). A novel interaction or architectural decision with no precedent. Build 2-3 competing prototypes and compare before committing.
- **Build the Lever** (`references/build-the-lever.md`). Any non-trivial work. Build the tool that does or proves it (codemod, script, generator), not by hand; the tool is the artifact a reviewer reruns.

**Architecture**

- **Model the Domain** (`references/model-the-domain.md`). Writing stateful logic, or code that branches a lot or repeats a shape assumption across files. Encode the domain in a structure (state machine, typed model, table or registry, reducer, boundary, the right collection) instead of scattered conditionals.
- **Boundary Discipline** (`references/boundary-discipline.md`). Wiring validation, error handling, or framework adapters. Guards at system boundaries, trust internal types, keep business logic pure.
- **Type System Discipline** (`references/type-system-discipline.md`). Designing types or a signature in any typed language. Make illegal states unrepresentable, brand primitives, parse external data at boundaries.
- **Make Operations Idempotent** (`references/make-operations-idempotent.md`). Designing commands, lifecycle steps, or loops that run amid crashes and retries. Converge to the same end state.
- **Migrate Callers Then Delete Legacy APIs** (`references/migrate-callers-then-delete-legacy-apis.md`). Introducing a new internal API while old callers exist. Migrate and delete in one wave.
- **Separate Before Serializing Shared State** (`references/separate-before-serializing-shared-state.md`). Concurrent actors might write the same file, branch, key, or object. Eliminate the sharing first.

**Verification**

- **Prove It Works** (`references/prove-it-works.md`). After a task, before declaring done. Verify against the real artifact, not a proxy or "it compiles".
- **Fix Root Causes** (`references/fix-root-causes.md`). Debugging. Trace each symptom to its root cause, reproduce first, ask why until you reach it.
- **Sequence Work into Verifiable Units** (`references/sequence-verifiable-units.md`). Multi-step work (sweeps, migrations, runs of similar edits) and how you stack commits and PRs. Break work into small units that each end in a check, verify each before the next, and order delivery so the sequence proves itself.

**Delegation**

- **Guard the Context Window** (`references/guard-the-context-window.md`). Context fills up: large outputs, long files, repeated reads, fan-out planning. Route bulk to subagents, keep summaries in the main thread.

**Meta**

- **Encode Lessons in Structure** (`references/encode-lessons-in-structure.md`). You catch yourself writing the same instruction a second time. Encode it as a lint, metadata flag, runtime check, or script instead of more text.

## Candor

**No is an acceptable answer.** Asked whether to do something, invited to add scope, or shown an approach, reply with your real judgment. Decline, push back, or say "this doesn't earn its place" when true. A recommendation is a judgment, not a validation. Agreement is not the default, candor over sycophancy.

## Writing the reply

Write the reply clean as you draft it. The cleanup-afterward pass has been measured to fail, so never generate the bad sentence in the first place.

- **Short declarative sentences.** One thought per sentence, ended with a period.
- **The long-dash character is banned outright.** Two cases. A file-list bullet joining a filename to its description with a dash. Write it as a sentence ("`main.js` owns persistence and the IPC handlers"). A bold section header joined to its text by a dash. Write the header as its own sentence ("**Verification.** End to end via CDP").
- **A colon as a mid-sentence connector is also out** (unslop rule 14). A colon before a list is fine.
- **Terse is not an excuse to drop content.** Short sentences, but every section the task's reply needs stays: details, tradeoffs, choices, open decisions.
- **Frame impact for the consumer and the maintainer.** Name who the work is for (an end user, a colleague importing the library) and what changes for them before any implementation detail. Then what the next engineer who owns this code inherits. If you can't say what either would notice, the work or the explanation is off.
- **Never fabricate a link, citation, or transcript reference.** Link only artifacts you produced or read this session.

When a PR exists, link it as `https://github.com/<owner>/<repo>/pull/<number>`.

## Comments

Comments follow the same rule as the reply. Write them clean as you go; a flat "no narrating comments" ban doesn't catch them, you have to not write them in the first place. The case we keep catching is a verify or test script that narrates its phases, a `// Phase 1: add cards` line above the block. Delete it; the assertion or log string is the only doc you need. Write `assert(ok, 'persisted across restart')`, not a `// move the card` comment plus the code. This applies to every file you produce, including a delegate's diff and the verify script. Keep a comment only for a non-obvious *why* the code can't show.

- The implementation is the documentation. Do NOT add a comment by default. Add one ONLY where its absence would cause a wrong implementation: a non-obvious invariant, a money/rounding/tax rule, timezone semantics, an ordering/race constraint, a third-party API workaround, a security rationale, or "must stay in sync with X". When you do: one line, state the fact, no preamble, no restating the code.
- Banned: comments that restate the next line, section banners, step narration (`// 1. validate`), JSDoc that only re-lists the signature or types, ticket/changelog chatter, commented-out code.
- Tool directives (`eslint-disable`, `@ts-expect-error`, `prettier-ignore`, `@deprecated`, `TODO`/`FIXME` with real content) are not comments in this sense. Keep them. A suppression of a correctness or safety rule is a refactor target, not a keep.
- A comment that claims a constraint (`IMPORTANT`, `do not remove`, `do not change wording`, `talk to X before changing`) is not a keep. Encode the constraint as a type, test, or lint, then delete the comment.
- A surprise in our own code gets no explanatory comment. Rename, extract, type, or restructure until the behavior is obvious. Only behavior forced by an external dependency, platform, vendor, or protocol we cannot reshape earns a comment, with an issue or RFC link when one explains what code can't.
