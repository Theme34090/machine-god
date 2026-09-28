---
name: cc-frens
description: "Spawn a subagent by role (explore, code, judge, panel, sicko) on the model and harness configured for that role. Use whenever a skill says 'spawn per cc-frens' or a task needs a subagent."
---

# Frens

Maps a subagent role to a model and a runner. Skills name the role; this file decides what runs it.

The harness-to-vendor mapping is fixed. GPT models run only in codex, grok only in cursor, glm only in pi, Claude only as a native subagent. Each model is RL'd against its own harness's tool shape and degrades elsewhere.

## Roles

| Role | Used by | Model | Runner | Writes |
|---|---|---|---|---|
| `explore` | cc-how explorers, cc-why investigators | gpt-5.6-luna, max | codex | no |
| `code` | delegates that implement | grok 4.6 high | cursor | yes |
| `judge` | cc-how explainer, cc-why synthesizer, cc-show-me-your-work reviewer | fable | native | no |
| `panel` | cc-how critics, cc-blast-radius second opinions | N seats, in this order: sol high, opus high, glm 5.3 high, grok 4.6 high, fable high | codex, native, pi, cursor, native | no |
| `sicko` | cc-no-comments | gpt-5.6-luna, max | codex | no |

A role absent from the table runs on the parent's model. A skill or the user can override the model inline by naming one; the table is the default, not a lock.

`panel` with N seats takes the first N rows in order. Three seats means sol, opus, glm.

## Recipe

1. Write the prompt to `.context/frens/<slug>/prompt.md`. Pass file pointers, not inlined context. For `code`, `judge`, `panel`, and `sicko`, the first line is `Read ~/.agents/skills/cc-principles/SKILL.md in full before any work.` For every role except `code`, the prompt says the delegate must not write files. `explore` gets no principles pointer; it gathers facts and writes nothing.
2. Run the runner in the background with the command below. stdout or the `-o` file is the delegate's final message and the only thing the parent reads. stderr goes to `.context/frens/<slug>/err.log` and never enters the parent's context.
3. The parent owns the result. Read the artifact (diff, file, output), never pass through the delegate's self-report.

## Runners

**codex** (`explore`, `sicko`, the sol seat). Default sandbox is already read-only with approvals off; a write attempt returns a clean refusal, no hang. Do not pass `-s`.

```bash
codex exec --ephemeral --skip-git-repo-check -C <dir> \
  -m gpt-5.6-luna -c model_reasoning_effort=max \
  -o .context/frens/<slug>/out.md - < .context/frens/<slug>/prompt.md \
  2> .context/frens/<slug>/err.log
```

The sol seat uses `-m gpt-5.6-sol -c model_reasoning_effort=high`. Do not pass `--ignore-user-config`; delegates see the same rules the parent does.

**cursor** (`code`, the grok seat). Run per /grok — it owns the modes, flags, and the cost note. Paths stay `.context/frens/<slug>/`.

**pi** (the glm seat). No sandbox. `--tools read,bash` keeps grep and find available; `read` alone cripples exploration. The prompt's "do not write" line is the only guard, and a stray write shows in `git status`. pi silently accepts a misspelled tool name and runs tool-less, so copy the flag exactly.

```bash
pi -p --no-session --mode text --tools read,bash --model zai/glm-5.3:high \
  "$(cat .context/frens/<slug>/prompt.md)" > .context/frens/<slug>/out.md 2> .context/frens/<slug>/err.log
```

Never `--mode json`; it emits every token delta (67 KB for a one-paragraph answer).

**native** (`judge`, the opus and fable seats). The harness's subagent tool (Claude Code: the Agent tool with `model: fable` or `model: opus`), run in the background. Thinking level is whatever the harness gives; not pinned.
