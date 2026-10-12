---
name: grok
description: "Spawn a grok subagent in cursor. Write mode edits the caller's current workspace by default; a fresh worktree is the isolation fallback. Ask mode is a read-only reviewer. Use for /grok or 'ask grok'."
---

# Grok

Grok runs only in cursor — it is RL'd against cursor's tool shape and degrades elsewhere. Model is `cursor-grok-4.6-high` unless the caller names another.

## Modes

**write**. Point `--workspace` at the caller's current dir — the work lands where the caller is already looking. Create a fresh worktree instead (`git worktree add <path> -b <branch>`) only when the tree has uncommitted work a delegate shouldn't tangle with, or the diff must stay clean for review-before-merge. `-p --trust` writes without an approval prompt. `-f` is required: without it grok cannot run commands, so it never verifies its own work. First line of the prompt: `Read ~/.agents/skills/cc-principles/SKILL.md in full before any work.`

**ask** (read-only reviewer). `--mode ask` is read-only. The prompt must say the delegate writes nothing.

## Invocation

Write the prompt to a file first — file pointers, not inlined context. Default layout `.context/grok/<slug>/`; callers may substitute their own paths.

```bash
# write (current dir by default; pass a worktree path to isolate)
agent -p --trust -f --workspace <dir> --model cursor-grok-4.6-high --output-format text \
  "$(cat .context/grok/<slug>/prompt.md)" > .context/grok/<slug>/out.md 2> .context/grok/<slug>/err.log

# ask (read-only, any dir)
agent -p --mode ask --workspace <dir> --model cursor-grok-4.6-high --output-format text \
  "$(cat .context/grok/<slug>/prompt.md)" > .context/grok/<slug>/out.md 2> .context/grok/<slug>/err.log
```

Run in the background. stdout (`out.md`) is the delegate's final message and the only thing the parent reads; stderr goes to `err.log` and never enters the parent's context. The parent owns the result: read the artifact (diff, file, output), never pass through grok's self-report.

## Cost

Cursor's base prompt is about 65k cached tokens per turn and grok tends to over-explore (14 tool calls where luna used 3 on the same trivial task), so a write-mode spawn costs minutes and tens of thousands of cached tokens before real work starts. Chosen anyway; revisit with evidence from real runs.
