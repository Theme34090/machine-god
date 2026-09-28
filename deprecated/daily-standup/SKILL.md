---
name: daily-standup
description: Gather my work since yesterday (Claude/Codex sessions, Linear, Slack, GitHub PRs, last standup) and synthesize a standup — done / in progress / backlog / today's priority.
disable-model-invocation: true
---

# Daily standup

Pull every source since the **cutoff**, then synthesize one standup message in the four-bucket template. Run the gather steps first; do not draft the message until all six sources are collected (or explicitly marked empty).

**Cutoff** = default yesterday 00:00 local. `gather.py` prints the exact cutoff on its `## WINDOW` line — read it, derive `CUTOFF_DATE` (`YYYY-MM-DD`) from it, and reuse that same date/timestamp for every source below so the window is consistent. Honor a user override ("since Friday", "last 3 days") by passing `--since`/`--hours` to the script and matching it in the MCP/gh queries.

## Gather

**Trace dump for audit.** Every run persists each source's raw payload to `~/.claude/standup/raw/<today>/` so a later "why did it miss X?" can tell fetched-but-dropped from never-fetched. `gather.py` creates that dir and prints its path on a `# RAW_DIR:` line — capture it and drop every other source's raw result there (paths noted per step below) before synthesizing.

Run 1 first; 2–5 are independent — fire them together.

1. **Sessions + my commits (deterministic).** Run `python3 ~/.claude/skills/daily-standup/gather.py` (add `--hours N` / `--since ISO` on override). It emits touched Claude + Codex sessions grouped by worktree (with sampled human prompts) and my git commits since cutoff, hash-deduped across worktrees. It also auto-writes its digest to `RAW_DIR/sessions.txt`.
   _Done when:_ you have the WINDOW cutoff, the `RAW_DIR` path, and the session/commit digest in hand.

2. **Linear — issues assigned to me.** `mcp__linear-server__list_issues` with `assignee:"me"`, `updatedAt:"-P2D"` (or match the window), `orderBy:"updatedAt"`, `limit:50`. Bucket by state type: `completed`/`canceled` → done, `started` → in progress, `unstarted`/`backlog` → backlog. Note `priority` 1–2 (urgent/high) for today. → dump raw result to `RAW_DIR/linear.json`.
   _Done when:_ every returned issue is bucketed by state and the raw payload is written.

3. **Slack — my activity + what's aimed at me.** Invoking this skill is your consent to search private channels + DMs.

   **First resolve your own Slack user_id** — call it `SLACK_UID`. Source of truth: the `slack_search_public_and_private` tool description states it verbatim ("Current logged in user's user_id is `U…`") — read it from there. Fallback: `slack_search_users` with your own display name. Substitute `<@SLACK_UID>` into every query below. Never hardcode a specific ID — this is what makes the skill portable across users.

   Three searches (`sort:"timestamp"`, `mcp__plugin_slack_slack__slack_search_public_and_private`) — all three matter, they cover different surfaces:
   - `from:<@SLACK_UID> after:CUTOFF_DATE` — what I said/committed to / shipped / reported.
   - `<@SLACK_UID> after:CUTOFF_DATE -from:<@SLACK_UID>` — **channel @-mentions of me.** `to:` does NOT catch these; this is where a colleague pinging me in a channel thread ("don't forget to flip the flag") lives. Skipping it drops real action items. (The bare `<@SLACK_UID>` mention-token needs the resolved ID — a `me` alias won't match here.)
   - `to:<@SLACK_UID> after:CUTOFF_DATE` — DMs + group-DMs aimed at me.
   → dump each search to `RAW_DIR/slack-from.json`, `RAW_DIR/slack-mentions.json`, `RAW_DIR/slack-to.json`.
   _Done when:_ all three ran and dumped; every ask/ping aimed at me is captured as a candidate action (backlog or today). An @-mention asking me to DO something outranks a merged PR for today's priority.

4. **GitHub PRs.** `gh search prs --author=@me --updated=">=CUTOFF_DATE" --json number,title,state,url,createdAt,closedAt,repository --limit 40 | tee RAW_DIR/prs.json`. `state`: `MERGED`/`CLOSED` → done, `OPEN` → in progress.
   _Done when:_ PRs split into merged/closed vs still-open and the raw JSON is written.

5. **Yesterday's standup.** Read the newest prior file: `ls -t ~/.claude/standup/*.md | head -1`, then read it. Its **today's priority** is the carryover check — anything there NOT shipped today rolls into in progress or today again. First run (no file): skip, note "no prior standup". → copy the file used to `RAW_DIR/yesterday.md`.
   _Done when:_ carryover items reconciled against what actually shipped, or first-run noted.

## Synthesize

Fold all six sources into the template below, most-important first. Attribute nothing you didn't find in a source. Mark a bucket `— none` rather than inventing filler.

- **One task = one bullet.** Never bundle unrelated tasks on a line — explode a "merge X + Y, start Z" into three bullets.
- **Each bullet stands alone.** A bare PR/issue number is not enough context — name what the work is: `merge #1083 — IAM scratch bucket for screenshots`, not `merge #1083`.
- **Do collapse the _same_ task across sources** — a merged PR + its commits + its Linear issue is one task, one bullet. That is dedup, not bundling.
- **Group under theme headers when a bucket runs long** (esp. _What done_ — a flat PR list doesn't scan). Cluster bullets under bold theme sub-headers (`*PDPA rollout*`, `*OCR accuracy*`, `*Misaka agent*`…) for glanceability. Themes organize; they never merge two tasks into one bullet. Short buckets stay flat.
- **Key themes off structure, not title words.** Cluster Linear issues by their parent epic (`parentId`) / `project` — a task's title may not name the epic (PAY-1756 "menu order" is a child of PDPA epic PAY-1295, so it themes under PDPA, not UI). Cluster PRs by repo/area. Title-keyword guessing is the last resort, only for items with no parent/project (loose PRs, agent commits).

```
📋 Standup — <today's date>

✅ What done (since <cutoff>)
- <shipped: merged PRs, closed issues, commits, resolved Slack threads>

🔧 In progress
- <open PRs, started Linear issues, active sessions, unfinished carryover>

📥 Backlog
- <assigned issues not started, asks in Slack not yet picked up>

🎯 Today's priority
- <top in-progress + urgent Linear + explicit Slack asks; 3–5 items max>
```

Bucket rules:
- **What done** — completed only: `MERGED`/`CLOSED` PRs, `completed` issues, commits that landed, threads I closed out. Not "worked on".
- **In progress** — open PRs, `started` issues, worktrees active in the digest, and yesterday's priorities not yet shipped.
- **Backlog** — `unstarted`/`backlog` assigned issues + unanswered asks directed at me. Flag urgent (priority 1–2) items.
- **Today's priority** — synthesize, don't dump: finish the nearest in-progress, then urgent Linear, then explicit Slack asks. Cap 3–5.

## Save + present

Write the synthesized standup to `~/.claude/standup/<today YYYY-MM-DD>.md` (this becomes tomorrow's "yesterday's standup"), then show it to the user. Offer to post it (Slack standup channel) only if asked.
_Done when:_ file written and message shown.
