---
name: codex-review
description: "Get a second-opinion code review from the codex CLI (external agent) on a diff. Use when the user says 'codex review', 'have codex review this', 'second opinion review', 'thermos with codex', or wants an out-of-band reviewer on the current branch/PR/commit. Thin wrapper around `codex exec review` / the thermos skill run inside codex."
allowed-tools: Bash(bash ~/.claude/skills/codex-review/run.sh:*), Bash(~/.claude/skills/codex-review/run.sh:*)
---

# codex-review

Shell out to the **codex** CLI to review code, and read back a clean verdict.
This is a *second opinion from a different model*, not a substitute for
`/code-review`. Runner hides the codex footguns (stdin hang, dir trust,
9k-line transcript). You just pick params and read the printed result.

## Invoke

Args are **positional or flagged** — bare tokens are classified by value, so
`/codex-review luna low` just works. When invoked as a slash command, pass
`ARGUMENTS` straight through:

```bash
bash ~/.claude/skills/codex-review/run.sh luna low            # model=gpt-5.6-luna, effort=low
bash ~/.claude/skills/codex-review/run.sh sol high thermos    # + thermos mode
bash ~/.claude/skills/codex-review/run.sh --effort low --mode normal --target main
```

All optional. Defaults shown.

| Param       | Default  | Bare tokens / values                                                    |
| ----------- | -------- | ----------------------------------------------------------------------- |
| model       | `sol`    | alias `luna` \| `terra` \| `sol` → `gpt-5.6-*`; or full id; or `--model` |
| effort      | `low`    | `low` \| `medium` \| `high` \| `xhigh` (codex reasoning, verbatim); or `--effort` |
| mode        | `normal` | `normal` = codex's built-in `review`; `thermos` = thermos skill in codex; or `--mode` |
| target      | `main`   | bare `main` \| `uncommitted`; branch/sha need `--target <ref>`          |
| concern     | none     | `--concern "<focus>"` only (multi-word); empty = codex infers           |

Bare branch/sha targets are flag-only (`--target`) to avoid misreading a
model alias or effort word as a ref.

The script prints codex's final verdict, then the path to the full
transcript. **Read the printed verdict — do not cat the transcript** unless
you need to verify a specific claim.

## Reviewing a PR

The runner never touches git — it reviews the **current** repo state. To
review a PR, check it out first (isolate it so it doesn't collide with other
work), then run with the default `--target main`:

```bash
# in a scratch/second worktree, detached so no branch lock:
git fetch origin pull/<N>/head && git checkout --detach FETCH_HEAD
bash ~/.claude/skills/codex-review/run.sh --mode thermos --target main --effort low
```

## Verify before trusting

codex findings are a second opinion, not ground truth. Before reporting a
finding as real, **check it against the actual diff** (grep the claim,
confirm the line). In past runs codex flagged a real-but-harmless lockfile
downgrade and a stale doc — both true, but severity was the caller's call.

## Notes / footguns baked in

- `</dev/null` — codex `exec` hangs forever ("Reading additional input from
  stdin") when stdin is a pipe (which the Bash tool provides). Runner guards it.
- dir trust — non-cwd/worktree paths aren't in codex's trusted-projects;
  runner injects `-c projects."<repo>".trust_level=trusted` so exec never
  stalls on a trust prompt.
- clean output — runner uses `-o FINAL`; you read that, not the transcript.
- `thermos` mode runs `codex exec` with `-s workspace-write` (thermos wants
  scratch); `normal` mode uses the `review` subcommand (read-oriented).
- Target classification is naive: an all-hex branch name (e.g. `abcdef`) is
  read as a commit sha. Rare; pass an explicit sha or a non-hex branch.
