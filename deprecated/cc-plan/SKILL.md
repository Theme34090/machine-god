---
name: cc-plan
description: "Plan a feature with the human in control: research the codebase, then product review, system architecture, program design, and vertical slices, each drafted by the agent and settled by grilling the user. Use for /cc-plan, 'plan this', 'write the plan', or before building anything larger than a oneshot."
---

# Plan

Thirty minutes of planning saves hours of review. The plan is a contract between the human and the agent. It aligns them before code exists and keeps the human in touch with how the code works at a high level. The agent drafts; the human argues with it; nothing is written as settled until the human settles it.

Four phases, always all four. The human says which to skip, not the skill.

## Output

Everything lands in `.context/plans/<slug>/` (globally gitignored):

- `research.md`. What exists today, written before any design.
- `plan.md`. Decisions, then one section per phase.
- Mockups and prototypes as sibling files, produced through the **cc-prototype** skill.

## Phase 0. Research

Read any file the user mentioned (a ticket, a spec, a Linear issue) fully, in the main context, before spawning anything. Then run the **cc-how** skill over every subsystem the request touches and write `research.md`.

Research documents the codebase as it exists today: what exists, where it lives, how it works, how components connect, with `file:line` references. No recommendations, no critique, no root-cause analysis. Document what is, not what should be.

Hand `research.md` back and stop. The human reads it before design starts. A bad line of research becomes thousands of bad lines of code; this is the highest-leverage review in the flow.

## How each phase runs

1. Draft the phase's section from the research and the request.
2. Grill. Call the Skill tool with "cc-grilling". Ask the whole frontier for this phase in one round, numbered, each with your recommended answer. Facts are yours to find (spawn per the **cc-frens** skill); decisions are the human's.
3. Revise the draft from the answers. Repeat until the frontier is empty and the human says the phase is settled.
4. Record every settled decision in the Decisions list with its reason.

The written plan carries no open questions. If one remains, the phase is not done.

## Phase 1. Product review

A short section that pins down what we're building and why, grounded in the product space, not the technical.

- **Problem to solve.** The actual user pain, in the user's terms.
- **What success looks like.** What can be read after shipping to decide the thing was worth building. Ideally a user outcome ("can do XYZ workflow in less time"); sometimes an error rate, a latency number, or "the support tickets about X stop".
- **Mockups.** Don't describe the screen, mock it up. Run the **cc-prototype** skill (UI branch) and link the files. The mockup is the understanding contract with whoever asked for the feature.

Technical details that surface here get jotted down for later phases, then back to what the user experiences. If tech decisions block product decisions, commit what you have and move to architecture, or settle feasibility with the **cc-prototype** skill (logic branch).

## Phase 2. System architecture

How the services, endpoints, schemas, queues, and stores talk to each other, without going down into program design. Sketch, don't narrate:

- Sequence of calls between components for the main flows.
- Contract and endpoint shapes (request, response, events).
- Data models and the transformations between them.

Fenced text blocks. Mermaid can lure you into a false sense that you are aligned; prefer plain sketches.

## Phase 3. Program design

The shape of the code before anyone writes it. Architecture is too high for this level, and an agent will otherwise decide it implicitly during implementation, at the most expensive time to change. Light visualizations in pseudocode:

- **Call-stack trees** for any orchestration or control-flow change. Diff syntax (`+` and `-` lines) when the interesting part is what's changing.
- **File-tree diffs** so the reader stays in touch with the layout of the codebase and where things live.
- **Types and method signatures** for the key new functions. The stuff too internal for architecture that an agent might still get wrong.
- **One line per new module** naming its data shape and the structure that organizes it (a state machine over scattered booleans, a table or registry over branching, a typed model over repeated shape assumptions). This is the model-the-domain rule from the **cc-principles** skill.
- **Seams.** Where the tests will sit: the public interface each test exercises.

None of these take long to produce. The agent drafts them; the human argues with them.

## Phase 4. Vertical slices

Models love horizontal plans: migrations, then service layer, then API, then frontend. Nothing can be touched until the end. Cut the work into vertical slices instead. Each slice is a thin, complete path you can poke at, and the order starts in the middle and works outward:

1. API contract serving mock data, tested with curl.
2. Frontend consuming the mock data, iterated in the browser.
3. API wired to the service layer (services serve mock data or behavior).
4. Migrations, services wired to the database.
5. Business logic.
6. Error handling.

Adapt the ladder to the feature; keep the property that every slice is testable on its own. For each slice, write two things:

- **Delivers.** One sentence: what you can see or call after this slice.
- **Check.** How the human verifies it: the command to run, or what to open and look at.

Files and functions live in program design, not here.

## The plan file

`plan.md` in this order: **Decisions** (one line each, what was decided and why), **Product review**, **System architecture**, **Program design**, **Slices**. Every section is the settled version. Write it per the **cc-technical-writing** skill and run the **cc-unslop** skill over it.

**Reply** after each phase: the artifact path, what the grilling settled, what the next phase will draft.
