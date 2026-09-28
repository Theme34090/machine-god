---
name: cc-autopilot
description: "Execute an approved plan autonomously: state done as a checkable predicate, drive to it without stopping, log every decision, pause only for irreversible or out-of-plan actions. Use for /cc-autopilot, 'execute the plan', 'run until done', 'going to bed', 'take it from here'."
---

# Autopilot

The human owns the plan. You own the execution. This skill grants autonomy only over work an approved plan already scopes; it does not change how ad-hoc requests are handled.

## Contract

- **Input.** An approved plan: a file path, or the plan already agreed in this conversation. No plan means no autopilot. Say so and ask for one.
- **Exit condition.** The plan's acceptance criteria, restated as a checkable predicate before the first iteration.
- **Stop and ask** for anything on the user's NEVER list (global `AGENTS.md`), any new dependency or fetch-and-execute, work outside the plan's stated scope, a plan assumption that turned out false, and every irreversible action below.
- **Output.** The branch pushed, the decision log at `.context/audits/<task-slug>.tsv` (the **cc-show-me-your-work** skill), and a reply that lists every decision you made that the plan did not. Open a PR only when the plan or the user says so. Never merge.

## Autonomy

**Just do it.** Use any MCP tool. Reversible work and external actions (team chat, ticket updates, kicking off evals) proceed without asking.

**Always pause** for irreversible writes: force-push to shared branches, deploys, data deletion, customer messages.

**Session overrides:** "Don't stop" / "going to bed" / "run until done" / "be fully autonomous" → keep going.

## Never block on the human

The human supervises asynchronously. Agents must stay unblocked: make reasonable decisions, proceed, and let the human course-correct after the fact. Code is cheap. Waiting is expensive.

**Why:** Every permission pause stalls the pipeline and makes the human the bottleneck. Since code changes are reversible and reviewable, a wrong decision usually costs less than blocking.

**Pattern:**
- **Proceed, then present.** Do the work, show the result. Don't ask "should I do X?" Do X, explain why.
- **Reserve questions for genuine ambiguity.** Ask only when you truly cannot infer intent from context.
- **Make the system self-healing.** When you notice a problem, log it and fix it in the next round.
- **Supervision is async.** The human reviews plans, diffs, and changes on their own schedule. Design workflows for review-after-the-fact.
- **Code is cheap, attention is scarce.** A wrong implementation costs minutes to fix. A blocked agent costs the human's attention to unblock.

**Boundaries:**
- **Irreversible actions** (force-push, delete production data, send external messages) still require confirmation.
- **Reversible actions** (write code, edit notes, split tasks) should proceed without blocking.
- **Product direction** comes from the human; *execution* should not block.

## The run

**You own the exit condition. Define done, then drive to it without stopping.**

1. State the exit condition as a checkable predicate before the first iteration (tests green, repro fixed, all N PRs merged, pixel-diff zero). A vague goal stalls; a predicate lets you stop.
2. Pick the wake mechanism your harness offers (Claude Code `/loop`, a watcher subagent, a heartbeat). An event to watch (CI, a merge, a ref advancing) gets a watcher subagent that wakes you on the event, with a long time-based heartbeat as fallback. No event gets a fixed-interval heartbeat sized to when the result is worth re-checking.
3. Each iteration makes the smallest change the evidence justifies, verifies it against the predicate, commits if it advanced, discards changes that didn't help. Belt-and-suspenders that "might help" gets reverted, not left to ride.
   Sequence the work via the **sequence-verifiable-units** principle (the **cc-principles** skill), verifying each unit before the next instead of batching checks at the end.
4. Mid-run discoveries are yours. Address broken skills, related bugs, flaky verifiers, review noise, tooling failures, orphaned follow-ups, and fixable drift yourself per the **cc-principles** skill. Put out-of-band fixes in their own PR. Do not park reversible work for the human or ask the user. Surface only irreversible actions, genuine product or preference calls no experiment can settle, the contract's stop conditions, or a real dead end. Keep the predicate as the main drive, and return to it after each side fix.
5. Checkpoint every iteration via the **cc-show-me-your-work** skill, a row for what changed and whether the predicate moved. A run with no trail can't be audited or resumed.
6. Stop when the predicate is met. A plateau is not a stop, so keep going and pivot your approach to push past it. Surface a genuine dead end rather than spinning, and never relax the predicate to declare victory.

**Reply:** the exit condition, iterations run, what landed, what was discarded, final predicate state, and every decision the plan did not make for you, each pointing at its log row.
