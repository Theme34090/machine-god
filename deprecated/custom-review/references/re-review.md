# Re-review mode — close-loop on prior threads + delta-scan

Loaded by `SKILL.md` Step 2.5 when the preflight script returns `mode: "re-review"`. This file is the authoritative spec for the re-review branch of `/custom-review`.

The preflight has already done all read-side work and emitted a manifest at `/tmp/custom-review-preflight-<PR_NUM>.json`. Read that file with the `Read` tool before doing anything else.

## Table of contents

1. Manifest schema (read this first)
2. Pipeline overview
3. Close-loop agent — spawn, prompt, output shape
4. Delta-scan agents — minor diffs from round-1
5. Triage extension — dedup against close-loop push-backs
6. Post step — order matters
7. Re-review body template
8. Edge cases

---

## 1. Manifest schema

```json
{
  "mode": "re-review",
  "skipReason": null,
  "headSha": "abc123...",
  "lastMarkerSha": "def456...",
  "roundNumber": 2,
  "forcePushDetected": false,
  "deltaScope": "def456...HEAD" | "full-pr-diff",
  "priorThreads": [
    {
      "threadId": "PRRT_kw...",
      "firstCommentDatabaseId": 3111782207,
      "isResolved": false,
      "isOutdated": false,
      "path": "apps/api/src/foo.ts",
      "line": 42,
      "originalSeverity": "high" | "medium" | "nit" | "question",
      "originalBucket": "Issue" | "Likely intentional",
      "fromRound": 1,
      "comments": [
        { "author": "...", "createdAt": "...", "body": "..." }
      ]
    }
  ]
}
```

`priorThreads` only contains threads that (a) are owned by this skill (parent review body carries the marker AND the parent review author matches the current `gh` identity) and (b) are not already resolved. Resolved threads are dropped — there's nothing to do with them.

---

## 2. Pipeline overview

```
manifest loaded  →  conventions gather (existing Step 3)  →  PR summary (existing Step 4)
                                                                ↓
              5 parallel agents — single message, Opus agents listed first:
                  #1 bug+invariant (Opus)         delta-scope only
                  #2 blast radius  (Opus)         delta-scope only
                  CLOSE-LOOP       (Opus)         prior threads
                  #3 conventions   (Sonnet)       delta-scope only
                  #4 git history   (Sonnet)       delta-scope only
                                                                ↓
                            Sonnet triage (extended: dedup vs close-loop push-backs)
                                                                ↓
                                          re-check eligibility
                                                                ↓
                            post step (see § 6):
                              1. POST replies via REST
                              2. resolveReviewThread mutations
                              3. POST new review (body + inline)
```

Delta-scan agents (#1–#4) use the existing prompts from `SKILL.md` § Step 5 unchanged — they consume `deltaScope` from the manifest instead of the full PR diff. When `forcePushDetected: true`, `deltaScope` is `"full-pr-diff"` and they fall back to `gh pr diff $PR_NUM`.

---

## 2.5. Scope judgment — skip delta-scan when low-risk

Before spawning agents in re-review mode, decide whether the 4 delta-scan agents fire this round. **Default-bias: run them.** Skip only when ALL of these hold:

- `forcePushDetected: false`
- The diff is small AND every modified file appears in `priorThreads[].path` (close-loop already verifies those locations)
- The diff doesn't touch high-risk areas: auth, payment, billing, migration, security, RBAC, encryption, money/Decimal handling, SQL/Prisma queries, or anything under `**/{auth,payment,billing,migrations,security}/**`
- No prior thread has `originalSeverity: high` (🔴 implies real risk surface; safety net should fire)

When skipping, spawn close-loop only (single-agent message), skip § 5 (triage), and pass close-loop output straight to § 6 (post step). Body footer must include the rationale — see § 7.

**Calibration:**

- 12 LOC, 4 UI nit fixes in one prior-thread file → **skip** ("Delta is 4 nit fixes confined to one prior-thread file.")
- 49 LOC fix to a Stripe webhook → **run** ("Touches payment code.")
- 30 LOC across 4 files outside priorThreads → **run** ("Surface outside close-loop coverage.")
- Reply-only re-fire (0 LOC) → **skip** ("No code changes; close-loop processes replies only.")

---

## 3. Close-loop agent — single Opus, general-purpose

Spawned **in the same parallel-message** as the 4 delta-scan agents. Five agents total in re-review mode.

**Launch order in the dispatch message:** all Opus agents first, then Sonnet. Order: `#1 bug` (Opus) → `#2 blast` (Opus) → `close-loop` (Opus) → `#3 conventions` (Sonnet) → `#4 history` (Sonnet). Sonnet agents go last so the slow Opus agents queue ahead.

**Inputs to the close-loop agent:**

- PR summary (from Step 4)
- Path to the manifest: `/tmp/custom-review-preflight-<PR_NUM>.json`
- Full PR diff via `gh pr diff $PR_NUM` (for deep-verification at the cited or replacement locations)

**Prompt skeleton:**

> You are processing prior review threads on PR #<N>. Read the manifest at `/tmp/custom-review-preflight-<PR_NUM>.json` and the full PR diff via `gh pr diff $PR_NUM`.
>
> For each thread in `priorThreads`:
>
> 1. Read the original finding — `comments[0].body`. It starts with a severity emoji (`🔴`/`🟡`/`🔵`/`❓`) and may include `**Likely intentional?**` bucket framing. The description follows. `originalSeverity` and `originalBucket` are pre-parsed in the thread object.
> 2. Read every subsequent comment. The LATEST state is what you judge against — prior reviewer push-backs are context, not gospel. If round 3+, the most recent author reply may be rebutting your own prior push-back; re-judge from the current code.
> 3. Read the current state of the cited file at HEAD. If `isOutdated: true`, the cited line was removed — look at the surrounding diff in `gh pr diff $PR_NUM` for the replacement code, and apply the heuristic at the **new location's** code, not the deleted one.
> 4. Apply the heuristic table below to pick `resolve` or `push_back`.
> 5. For `push_back`: compose a tight reply using the template below.
> 6. For `resolve`: optional one-sentence reply (empty string if none). For "Reviewer was wrong" rows, include a brief acknowledgment.
>
> **Heuristic table** (read row + column for the decision; "code change deep-verified" means you confirmed the new code addresses the original concern by reading it at HEAD):
>
> | Author response | 🔵 / ❓ | 🟡 | 🔴 |
> |---|---|---|---|
> | Code change addresses finding (deep-verified) | resolve | resolve | resolve |
> | Code change but original concern persists | push back | push back | push back |
> | No code, reply links a separate landed fix PR | resolve | resolve | resolve |
> | No code, reply "won't fix, tracking <issue>" | resolve | push back | push back |
> | No code, reply "by design because X" — X checkable in code | resolve | resolve if X verifies | resolve if X verifies |
> | No code, reply "by design because X" — X is just vibes | push back | push back | push back |
> | No code, reply "not a bug / intentional" with no reasoning | push back | push back | push back |
> | No code, no reply (ghosted) | NO ACTION | NO ACTION | NO ACTION |
> | Reviewer was wrong — finding misread the code | resolve + ack | resolve + ack | resolve + ack |
>
> **Ghosted threads:** emit nothing for that thread. The body summary counts them as "Still open" automatically.
>
> **Severity-driven rationale:** the difference between 🔵/❓ and 🟡/🔴 in the "won't fix" and "by design (vibes)" rows is intentional. 🔵 nits and ❓ questions only ask for engagement; any engagement (including "won't fix") closes them. 🟡 and 🔴 anchor on mergeability — "won't fix" without verifiable reasoning doesn't address the mergeability concern.
>
> **Outdated threads:** `isOutdated: true` means the cited line was removed. Don't treat it as auto-resolve. Apply the same rubric at the replacement location:
> - If the rewrite legitimately removes the concern → resolve with "Original anchor removed; concern no longer applies."
> - If the rewrite preserves the bug elsewhere → push back, referencing the new location.
>
> **`Likely intentional` bucket:** treat the same as `Issue`. The bucket framing was a question to the author; the author's reply (or code change) collapses it the same way Q7 says.
>
> **Push-back reply template:**
>
> ```
> <one sentence on what's still wrong OR what's missing from the reply>
>
> > <quote of the original concern OR the author's reply being rebutted>
>
> <optional second sentence with a concrete next step if useful>
> ```
>
> **Output shape** — return a JSON array. Omit ghosted threads entirely (no entry at all):
>
> ```json
> [
>   {
>     "threadId": "PRRT_kw...",
>     "firstCommentDatabaseId": 3111782207,
>     "decision": "resolve" | "push_back",
>     "reply": "<reply text, empty string if no reply for a resolve>",
>     "rationale": "<one short line — for triage's dedup pass; not posted>"
>   }
> ]
> ```
>
> `firstCommentDatabaseId` is copied through from the manifest — the post step needs it to POST a reply via REST (replies attach to the *first comment* of the thread, not to the thread node ID).
>
> `rationale` is one line summarizing why you picked the decision; triage uses it to detect overlap with delta-scan findings (same file:line + same root cause).

---

## 4. Delta-scan agents — minor diffs from round-1

Same prompts as `SKILL.md` § Step 5 (#1 bug, #2 blast, #3 conventions, #4 history). Two changes for re-review mode:

1. **Diff scope.** Replace `gh pr diff $PR_NUM` in the agents' prompts with:
   - `git diff <deltaScope>` when `deltaScope` is `<sha>..HEAD`
   - `gh pr diff $PR_NUM` when `deltaScope` is `"full-pr-diff"` (force-push)
2. **Conventions agent path list.** Re-derive from `git diff --name-only <deltaScope>` (or `gh pr diff $PR_NUM --name-only` for force-push).

No other prompt changes. The agents stay diff-relative.

If `deltaScope` is `<sha>..HEAD` and `git diff <deltaScope>` is empty (reply-only re-fire), delta-scan agents will return zero findings. That's expected — close-loop is doing all the work in that case.

---

## 5. Triage extension — dedup against close-loop push-backs

Triage receives one additional input: the close-loop agent's JSON output.

Add this to the triage prompt **after** the existing dedup rule:

> **Additional dedup for re-review mode.** You'll receive the close-loop agent's output (`resolve` / `push_back` decisions). After the dedup pass across the 4 delta-scan agents, **also dedup against close-loop push-backs**: if a delta-scan finding's `(file, line, root cause)` overlaps a close-loop push-back at the same location with the same root concern, drop the delta-scan finding. The thread reply is the canonical surface for that issue — duplicating it as a fresh inline comment is noise.
>
> Use `rationale` on the close-loop output to judge overlap.
>
> Close-loop output does NOT get bucketed or graded by you. Its decisions are inherited from the original thread's severity and bucket.

Triage's other responsibilities (bucket, grade, sort) unchanged.

---

## 6. Post step — order matters

The body text claims "Resolved: K threads" — that must be true by the time the body posts.

```
For each close-loop output entry (in order):
  if reply is non-empty:
    POST reply via REST:
      gh api --method POST \
        "repos/$OWNER/$REPO/pulls/$PR_NUM/comments/$FIRST_COMMENT_ID/replies" \
        -f body="$REPLY"

  if decision == "resolve":
    Call resolveReviewThread mutation:
      gh api graphql -f query='
        mutation($threadId: ID!) {
          resolveReviewThread(input: {threadId: $threadId}) {
            thread { id isResolved }
          }
        }' -f threadId="$THREAD_ID"

After all replies + resolves are done, post the new review per references/posting.md.
  - Body: re-review template (§ 7 below) — NOT the round-1 template.
  - Inline comments: triaged delta-scan findings (close-loop output is NOT included here).
  - "event": "COMMENT" (same as round-1).
```

Counts the body must report:

- `K` = count of `decision == "resolve"` entries from close-loop.
- `U` = `priorThreads.length` − K − (count of ghosted threads not emitted by close-loop). Practically: `U` = total non-resolved prior threads after this round runs.
- `X` / `Y` / `Z` / `W` = triaged delta-scan finding counts for 🔴 / 🟡 / 🔵 / ❓.

If `decision == "push_back"`, the thread stays open and counts toward `U`.

**Failure-mode notes:**

- If a REST reply POST 4xx's, log it and continue with the resolve mutation anyway — the resolve still has value. Don't bail the whole post step on a single comment failure.
- If `resolveReviewThread` errors with "thread already resolved", treat as success (race with the author resolving manually).
- If posting the new review 422's, fall through to `references/posting.md` § 3 — same handling as round-1.

---

## 7. Re-review body template

```markdown
### Code review — round <N>

Resolved: <K> threads (verified fixes / accepted replies)
Still open: <U> threads from prior rounds (see thread replies)
New: <X> 🔴, <Y> 🟡, <Z> 🔵, <W> ❓ findings (see inline)

<details>
<summary>Context (<M>) — pre-existing or outside this PR's scope</summary>

#### Pre-existing

1. 🔴 <description> — `<file>:<line>`
...

#### Outside change

1. 🟡 <description> — `<file>:<line>`
...

</details>

<sub>Automated review via <code>/custom-review</code> (round <N>).</sub>

<!-- custom-review:<NEW_HEAD_SHA> -->
```

**Rules:**

- Suppress any of the three breakdown lines (Resolved / Still open / New) where the count is zero. If all three are zero, the skill should have skipped earlier — defensive: drop the count block entirely.
- The "New:" line follows the same zero-omission convention as round-1 (`Found <H> 🔴, <M> 🟡 ...`): drop any severity with count zero, drop the whole line if every severity is zero.
- If `forcePushDetected: true`, add a single italic note **below** the three-line breakdown:
  ```
  _Note: force-push detected; this round scanned the full PR diff._
  ```
- If delta-scan was skipped per § 2.5, add this italic note instead (mutually exclusive with the force-push note):
  ```
  _Delta-scan skipped: <rationale>. New findings outside prior threads not scanned._
  ```
- The hidden marker `<!-- custom-review:<NEW_HEAD_SHA> -->` MUST be present — that's how the next round's preflight finds this round.
- Round number is `manifest.roundNumber` (it was incremented at preflight time, so it already reflects the round being posted).
- Footer text appends `(round <N>)` to distinguish it from round-1 reviews in the PR's review list.

---

## 8. Edge cases

| Case | Handling |
|---|---|
| Marker matches HEAD, no new author replies | Preflight returns `mode: skip`; this file isn't loaded. |
| Marker matches HEAD, new author replies exist | Re-review fires; `deltaScope = <sha>..HEAD` (empty); delta-scan returns 0; close-loop carries the work. |
| Marker != HEAD, force-push detected | `deltaScope = full-pr-diff`; close-loop unaffected (thread metadata persists across rewrites); body notes force-push. |
| All prior threads resolved by close-loop, zero new delta-scan findings | Still post body (just "Resolved: K threads") + marker so the next preflight sees this round. |
| Prior thread `isOutdated: true`, rewrite removed the concern | Resolve with "Original anchor removed; concern no longer applies." reply. |
| Prior thread `isOutdated: true`, rewrite preserved the bug elsewhere | Push back referring to the new location. |
| Author rebutted our prior push-back (round 3+) | Same heuristic table — re-judge against latest code state. Prior push-back is context, not gospel. |
| Thread has no parent review (defensive — shouldn't happen) | Preflight excludes it via the marker+login filter. |
| Preflight script fails | SKILL.md hard-exits; do not fall through to round-1 silently. |
| `Likely intentional` bucket threads | Same heuristic as `Issue` bucket. |
| Close-loop returns zero entries (all threads ghosted) | All ghosted threads count toward "Still open: U". Delta-scan may still have findings to post. |
