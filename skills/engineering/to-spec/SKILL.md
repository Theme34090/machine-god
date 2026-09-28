---
name: to-spec
description: "Turn one slice of a grand plan into an implementation spec: no interview, synthesis from the grand plan and the codebase, then iterate on the user's feedback."
---

A **grand plan** is an epic: goal, acceptance criteria, a task breakdown into slices (one PR each), and a proposed high-level shape of the implementation. This skill takes one slice and writes its spec. The grand plan is the source of truth for settled decisions; the spec fills in what the slice needs beyond it.

The grand plan should be in context and the slice named in the arguments. If either is missing, ask.

## Process

1. Explore the repo around what the slice touches, so the spec describes the codebase as it is. Use the project's own vocabulary throughout.

2. Write the spec with the template below. Where the grand plan is silent or marks something TBD that this slice needs, make the call and keep going. Each decision carries its reason.

3. Write it to the path the user gives; ask for one if none was given. Write the file per the cc-technical-writing skill. Leave the grand plan untouched.

4. Reply with one list: every call you made on the way to the spec, and why. This is how the user reconstructs your path. It lives in the reply, never in the spec.

5. Revise on feedback. The spec is done when the user says so.

<spec-template>

## Goal

What this slice delivers, in one paragraph, and what the grand plan it serves is.

## Acceptance Criteria

Only the criteria this slice satisfies, restated from the grand plan in this slice's terms, from user-perspective at product level, not implementation checklist, one scenario each in Gherkin:

```gherkin
Given <precondition>
When <action>
Then <observable outcome>
```

## Implementation Decisions

A list of decisions, each with its reason. Can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Name modules and functions, never file paths: paths go stale, and where new code lands is the implementer's call.

When a decision is clearer as a sketch than as prose, add one. Read `references/system-architecture.md` for how components talk (call sequences, contracts, data models) or `references/program-design.md` for the shape of the code (signatures, types, seams).

## Testing Decisions

The acceptance criteria are the test list; this section says how they get proven, so it stays short:

- The seam: the public interface the tests exercise, and what they assert (what renders, what the call receives). What each test proves, never how: no case lists, no tables.
- Prior art: one existing test to model on, and only one the standard would pass
- Exceptions: a scenario that gets no automated test and why, or a test beyond the scenarios and which criterion it serves
- Manual checks: only what is provable by looking

Scaffolding a later slice deletes gets no test of its own.

## Out of Scope

What belongs to other slices, by slice number, so the implementer knows where to stop.

## Further Notes

`file:line` references to what exists today, so the implementer skips the search. Anything else that didn't fit above.

</spec-template>
