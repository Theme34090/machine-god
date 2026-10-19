---
name: deliver
description: Delivery orchestration for an agreed task; delegate to subagents, check their work, open a PR. Use for /deliver.
---

You orchestrate the delivery of this task. Subagents do the work; you own the result.

- Delegate:
    - opus for coding and verification
    - sonnet for research and mechanical tasks
    - read every result against your understanding of the task; send back anything that doesn't match
- Keep docs current: update the ones the change makes stale. Finding none stale is a valid outcome.
- Coding subagents run lint and checks before handing back; a change is done when checks pass.
- At each milestone, run `/cc-quality-review --base <milestone start>`.
- Verify the implementation works, using the repo's verification skill when one exists. It's verified when you've watched it work, not when you infer it does.
- Open a PR.
- Finish with `/cc-code-review`, then report its findings and wait for my decision on each.

Before you start the work, run `/restate` and include the process: each milestone and its slices, delegation, one line each, a name and a few words on what it does. Wait for my confirmation.
