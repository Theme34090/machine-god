---
name: cc-architect
description: "Design before implementing: three models sketch types, signatures, and module structure in parallel, a judge scores them, the best is grafted into one design, then implemented unattended."
disable-model-invocation: true
---

# Architect

Design before implementing. Three models each sketch the whole shape (types, function signatures, module boundaries with `not implemented` bodies and pseudocode) from the same prompt. Read every candidate, pick a base, graft the strongest parts of the others into it, then fill in code against the chosen sketch. If implementation proves the sketch wrong, throw it out and redesign.

The user answers once, at the start. After that the run is unattended: every later decision is logged in the synthesis note, never asked.

## Start

Open a todolist with one entry per step below before starting.

### 1. Ask

One `AskUserQuestion` call, all of these in it:

- **Grounding**: a path to an existing grand plan or research doc, or "run cc-how".
- **End point**: design only, or design + implement.
- **Constraints**: callers that can't break, banned dependencies, no-go areas.
- **Branch**: only when the current branch is the default branch. Name for the new branch.

Done when every item has an answer. Create the branch now if one was named.

### 2. Ground

With a grounding doc, read it in full; it is the grounding. Without one, run the **cc-how** skill over every subsystem the new code touches and produce the traced model it prescribes. Naming a file isn't grounding. If the design redefines ownership or layering, also run the **cc-why** skill on the existing shape so the rationale becomes a constraint, not a guess.

Skip only when the work is genuinely greenfield with no surrounding system to integrate.

Done when you can name every module the change touches, who owns its state, and every caller of the code it changes.

### 3. Frame

The candidates receive the same prompt, so the prompt is the contract.

1. Write `task.md` in the scratchpad: the artifact (a design package for <the change>), the grounding (path to the doc or the cc-how model inline), and the constraints from Ask.
2. Derive the rubric: 3-6 concrete gradeable criteria for *this* design. Candidates see only the task; the rubric is the picker's tool.
3. Run `scripts/fanout.sh prepare <task.md> -C <repo>`. It prints the run directory (`<run>` below) and assembles `<run>/prompt.md` from `references/runner-prompt.md`, `references/rationale-template.md`, `references/design-red-flags.md`, and the task. Write the rubric to `<run>/rubric.md`.

### 4. Fan out

In one message:

- `scripts/fanout.sh run <run>` in the background. It runs gpt-6.1-sol (medium) through codex and glm-5.3 (high) through pi in parallel, writing `<run>/sol.md` and `<run>/glm.md`. Exit 0 means both seats produced output; exit 1 or 2 is the number of failed seats, each named on stderr.
- A background Agent with `model: opus`, prompt: `Read <run>/prompt.md and follow it. Write no files.` Save its final message to `<run>/opus.md`.

If a seat fails, proceed with the rest and note the dropout in the synthesis note. With fewer than two candidates, re-run the failed seat once; "design it twice" is not optional.

### 5. Cross-judge

After every seat finishes, spawn one background Agent with `model: fable`: readonly, given `<run>/rubric.md` and the candidate files relabelled A, B, C (map recorded in `<run>/labels.md`, which the judge does not see). It scores each candidate per criterion and recommends a base with rationale. Save its answer to `<run>/judge.md`. It runs in parallel with your own reading in Pick.

### 6. Screen

Screen every candidate against `references/design-red-flags.md`. Assume the next contributor is an agent that sees only the files it opened, copies the nearest example, and takes the shortest path that compiles. Prefer the design where a change that looks right from one file is right for the whole repo.

Compare viable candidates on interface depth. Prefer the design that hides more complexity behind a smaller, simpler public surface. A rich interface can keep call chains short by concentrating capability instead of scattering it across layers.

### 7. Pick a base

Read every candidate end to end before picking.

Score each candidate against the rubric criterion by criterion, not on holistic feel. Compare against the judge. Agreement on the base confirms the pick. Disagreement means one of you is biased or the rubric was ambiguous. Read both rationales before deciding.

Pick the base on which candidate a future maintainer can extend most easily without breaking invariants. Prefer the cleaner boundary or smaller API when two feel tied, per the Laziness Protocol.

### 8. Graft

Walk each losing candidate once more and identify what is worth porting into the base. The signal is usually one or two things per candidate, not most of it.

Fold each graft in by hand, per the Redesign from First Principles principle. Don't paste mechanically. The result has to remain coherent under one mental model.

When the candidates converge on the same shape, that is a strong agreement signal. Note the convergence and ship the consensus shape. No graft is needed. When they wildly diverge, Frame was under-specified. Reframe and re-run rather than averaging the divergence.

Write `<run>/synthesis.md` per `references/rationale-template.md`. Its "Synthesis decision" section names the base, the judge's verdict, each graft with its source candidate, each rejection and why, and any dropouts.

### 9. Scaffold

The caller's usage is written first and the type sketch derived from it. One file with new types and signatures for small changes. Module map plus type definitions for larger work. Write the sketch into the repo with `not implemented` bodies, and the rationale alongside it.

Verify the scaffold per Prove It Works: it type-checks or compiles, and the usage section's call sites compile against it. Commit it as its own commit.

With end point "design only", stop here and report.

### 10. Implement against the sketch

Replace `not implemented` bodies with code, pseudocode with logic. The synthesized sketch is the contract. Commit one logical change at a time once its checks pass.

Deviations from the sketch are signal worth surfacing, not friction to absorb silently. If a function needs a parameter the sketch didn't anticipate, decide whether the sketch was wrong, the requirement was missed, or the implementation is overreaching. Apply a deviation that changes the sketch's public surface, log it in `<run>/synthesis.md` with its reason, and count it toward the scrap signals.

### 11. Scrap when the architecture is wrong

If implementation keeps producing friction the sketch can't absorb, throw the sketch out. Don't bolt fixes onto a wrong design, per the Redesign from First Principles and Fix Root Causes principles.

The signal is a *pattern*, not single instances. Tells:

- The same shape of workaround appearing repeatedly across unrelated code.
- Multiple unrelated edge cases that all need special-case branches.
- Types that need escape hatches (`any`, casts, optional fields always set in practice) to compile.
- The "we need a lock" reflex when the sketch said the state wasn't shared.
- Callers having to know the abstraction's internal rules to use it.
- Two or more independent deviations of the same shape across the implementation.

Use judgment. A few edge cases don't condemn an architecture. Some problems are legitimately complex. Complexity in the data is not complexity in the design.

On the first scrap:

1. Re-run the **cc-how** skill over what's been built.
2. Redesign as if the new constraints had been day-one assumptions.
3. Subtract before adding, per the Subtract Before You Add principle. The new sketch should be smaller than the old one before it grows.
4. Return to Frame with the scrap evidence added to the task, and re-run from there.

On a second scrap, stop and report the evidence instead of redesigning again.

## Report

Lead with every public-surface deviation from the sketch. Then: the run directory, the base and grafts, the commits, the verification result, and any dropout or scrap.
