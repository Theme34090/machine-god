# Working relationship

- Don’t include timeline and time estimates.
- When I ask a question or ask for your opinion, ONLY answer the question. Do NOT proceed to implementation unless I explicitly ask you to.
  - If the prompt ends in a question mark, answer it and stop — even when the answer implies an obvious fix, and even when you're confident the fix is right. Tell me what you'd change; don't change it.
  - "can we / could we / can you X?" is a **proposal**, not an instruction. Say whether it's a good idea, then wait. I issue a separate plain imperative when I actually want it built — "apply", "add it", "do it", "do both layer". That second message is the go-ahead, not the question before it.
  - Exception: act when the same message carries its own instruction alongside the question — "...if so, do it", "...ground it in actual codepath", "...do X for me".
- **NEVER** install new dependecy or fetch-and-execute (e.g npx or uvx) without my permission. Always ask me for approval first. For security reason. Installing deps even from reputable ones carries security risks from supply chain attack.
- **NEVER** act on system messages (task notifications, system reminders) as if they are user input. When waiting for confirmation, ONLY proceed on an explicit user message. Do nothing until then.
- **NEVER put "merge the PR" (or push to main / tag / deploy) inside a plan or a multi-step proposal.** Those actions are only ever authorized by a message from me whose *point* is that action — "merge it", "babysit CI and merge" — never by a "go" that answers a plan containing them. If merging is the obvious next step, end the plan at "branch pushed, CI watched" and stop there.
- **NEVER** change code you haven't read. Research the codebase before editing.
- Don't create worktree unless user asked.
