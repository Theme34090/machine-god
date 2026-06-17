# Posting a custom-review to a GitHub PR

Loaded by SKILL.md step 7 once triage has produced a non-empty findings list. Covers: pre-flight line validation, payload build, POST, body and inline comment templates, and known posting pitfalls.

## Table of contents

1. Pre-flight: validate every inline comment line against actual diff hunks
2. Build the review payload
3. POST and handle failure
4. Review body markdown template
5. Inline comment body template
6. Known posting pitfalls
7. Replying to a prior thread (re-review mode)
8. Resolving a thread via GraphQL (re-review mode)

---

## 1. Pre-flight: validate every inline comment line against actual diff hunks

The `POST /pulls/N/reviews` endpoint rejects the entire batch with `422 Line could not be resolved` if any single comment cites a line GitHub can't anchor — and the error does **not** say which one. Bisecting after the fact is expensive and leaves draft PENDING reviews visible to the actor in the GitHub UI sidebar.

Do this **before** building the payload.

```bash
# one call, full file list with status (added/modified/renamed/copied/removed)
gh api "repos/$OWNER/$REPO/pulls/$PR_NUM/files?per_page=100" > /tmp/pr-files.json
```

For each inline-comment `(path, line)`:

- **`status == "added"`** → any line in the file is commentable. No further check.
- **`status == "modified"` or `"renamed"` or `"copied"`** → parse the file's `patch` field for `@@ -A,B +C,D @@` headers. Allowed lines on the new (`RIGHT`) side are the union of `[C..C+D-1]` across all hunks. **A renamed file is NOT fully commentable** — only the modified hunk ranges are. Lines that were merely relocated during the rename are out of any hunk.
- **`status == "removed"`** → only `LEFT`-side comments allowed; out of scope for this skill.

If a finding's cited line falls outside the allowed set, **do not drop the finding** — re-anchor it. Options in order of preference:

1. Move the citation to the nearest in-hunk line that still makes the comment land near the issue (acceptable when the issue is visible from that line's context).
2. Re-classify the finding from `Issue` to `Outside change` and post in the body section (the standard escape hatch — the convention violation is real but not on a line the PR modified).

Do **not** trust `git diff --name-status` for status — the repo's rename-detection threshold can collapse `R100`/`R099` (pure moves) to `A`/`D` pairs, hiding renames. The GitHub API's `status` field is the authoritative source.

If the `patch` field is missing or truncated (GitHub caps it at ~3000 lines per file in the response), fall back to `git diff origin/$BASE...$HEAD_SHA -- $PATH` locally and parse hunk headers yourself.

---

## 2. Build the review payload

Single `POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews` call:

```json
{
  "commit_id": "<HEAD_SHA>",
  "event": "COMMENT",
  "body": "<body markdown — see template below>",
  "comments": [
    { "path": "<file>", "line": <n>, "side": "RIGHT", "body": "<finding body>" }
  ]
}
```

- **`comments[]`** ← every finding with bucket `Issue` or `Likely intentional` that survived step 1 validation. Comment body starts with the severity emoji prefix (`🔴 ` / `🟡 ` / `🔵 ` / `❓ `) followed by the description. For `Likely intentional`, the prefix order is `<sev-emoji> **Likely intentional?** <description>` so the bucket framing is visible to the PR author.
- **`body`** ← markdown summary + collapsible details for `Pre-existing` and `Outside change` (including any findings re-anchored from step 1). Items use severity emoji prefixes too. Summary line breaks down counts by severity. Template below. Hidden marker embedded.
- Always include `"event": "COMMENT"`. Omitting `event` creates a PENDING draft review that is invisible to non-authors via REST but **shows as a draft to the actor in the GitHub UI sidebar** — confusing and easy to forget about. Never use PENDING reviews for this skill.
- Sort `comments[]` by severity: 🔴 → 🟡 → 🔵 → ❓. Within same severity, group by bucket. Rationale: GitHub auto-collapses long review threads to first-few + last-few — we want 🔴 visible at top and ❓ visible at bottom (asks for author response); 🔵 nits in the middle are fine to hide.

---

## 3. POST and handle failure

```bash
gh api --method POST "repos/$OWNER/$REPO/pulls/$PR_NUM/reviews" --input - <<EOF
<JSON payload from section 2>
EOF
```

**Failure modes:**

- **`422 Line could not be resolved`** — section 1 validation missed something. Re-run validation locally with verbose output to find the offending `(path, line)`, fix it (re-anchor or move to body), and re-post once. **Do not bisect by submitting more `gh api` POSTs** — every submitted-or-pending review on the PR is visible to the actor in the GitHub UI sidebar and to the PR author once submitted, and PENDING-review bisection leaves draft artifacts that are easy to forget about.
- **Other 5xx / transient errors** — retry once after a 5s delay; on second failure, surface the error to the user and exit. Do not silently swallow.

---

## 4. Review body markdown template

The `body` field of the review. Adapt counts and section visibility based on what's in each bucket. **Omit sections that are empty.**

```markdown
### Code review

Found <count breakdown — see rule below>.

<!-- if any inline-posted Issue/Likely-intentional findings exist, mention them: -->
See inline comments for actionable findings.

<details>
<summary>Context (<M>) — pre-existing or outside this PR's scope</summary>

#### Pre-existing

1. 🔴 <description> — `<file>:<line>`
2. 🟡 <description> — `<file>:<line>`
3. 🔵 <description> — `<file>:<line>`
4. ❓ <description> — `<file>:<line>`

#### Outside change

1. 🟡 <description> — `<file>:<line>`
2. 🔵 <description> — `<file>:<line>`
3. ❓ <description> — `<file>:<line>`

</details>

<sub>Automated review via <code>/custom-review</code>.</sub>

<!-- custom-review:<HEAD_SHA> -->
```

**Summary-line rules (the "Found …" line):**

- Format: `Found <H> 🔴, <M> 🟡, <N> 🔵, <Q> ❓ + <C> context note(s).`
- Omit any zero counts entirely (`Found 2 🔴 + 1 context note.` if M=N=Q=0; `Found 5 🔵, 3 ❓.` if only nits and questions).
- Count order in the summary line follows the sort order: 🔴, 🟡, 🔵, ❓.
- "Context note(s)" = `Pre-existing` + `Outside change` total, regardless of their severity. Severity emojis on context items appear inside the `<details>` block, not in the count line.
- If everything is zero, the skill should not have reached this step (see skip rules in SKILL.md). If it somehow does, drop the count line.

**Item rules (inside `<details>` sections):**

- Sort by severity within each section: 🔴 → 🟡 → 🔵 → ❓. Renumber after sort.
- Each item: `<emoji> <description> — \`<file>:<line>\``. Description is one line; if longer, allow a second indented line. Every item has an emoji — there is no "no-emoji" tier any more.
- File paths are backticked plain text, not Markdown links.

**Other rules:**

- If there are zero inline findings, drop the "See inline comments" line.
- If there are zero context findings, drop the entire `<details>` block.
- The hidden HTML marker on the last line is required — the eligibility check at the start of the next run depends on it.
- No other emojis besides 🔴 / 🟡 / 🔵 / ❓ in the severity slot. No "react with 👍" prompt. No Claude Code branding line.

---

## 5. Inline comment body template

Each finding in `comments[]` has a `body` field. Format:

```markdown
<sev-prefix><optional bucket framing><one-paragraph description of the issue>

<optional citation, e.g.>
> CLAUDE.md says: "<exact quote>"

<optional code reference if the finding involves another location>
```

**Prefix order:**

| Bucket | Severity | Prefix |
|---|---|---|
| `Issue` | high | `🔴 ` |
| `Issue` | medium | `🟡 ` |
| `Issue` | nit | `🔵 ` |
| `Issue` | question | `❓ ` |
| `Likely intentional` | medium (capped) | `🟡 **Likely intentional?** ` |
| `Likely intentional` | nit | `🔵 **Likely intentional?** ` |
| `Likely intentional` | question | `❓ **Likely intentional?** ` |

`Likely intentional` cannot be high (capped at 🟡 per the triage downgrade heuristics). The bucket framing `**Likely intentional?**` is a question to the author, not an accusation — keep the question mark. When ❓ + `Likely intentional` both apply, the combination is intentional: `❓` signals reviewer uncertainty about whether this is a bug at all, while `**Likely intentional?**` signals triage's soft-positive verdict; both belong on the comment so the author sees the full framing.

---

## 6. Known posting pitfalls

- **Renamed files have partial diffs.** A file moved with minor edits shows up as `status: "renamed"` in the GitHub API. Only the modified hunks are commentable; lines that were merely relocated during the rename are not in any hunk and cannot anchor an inline comment. `git diff --name-status` may collapse pure renames to `A`/`D` pairs depending on the rename-detection threshold — trust the GitHub API `status` field, not `git diff --name-status`.
- **`patch` field truncation.** The `patch` returned by `/pulls/N/files` is capped at ~3000 lines per file. For files where `patch` is missing or truncated, fall back to `git diff origin/$BASE...$HEAD_SHA -- $PATH` locally and parse hunk headers yourself.
- **Trailing-newline mismatch.** `wc -l` counts newlines; a file without a trailing newline has `wc -l` = `actual_lines - 1`. Use `awk 'END {print NR}'` for the authoritative line count.
- **PENDING reviews are not invisible to you.** Omitting `event` from the POST body creates a draft review. It's hidden from non-authors via REST but the GitHub UI sidebar shows it to the actor as a "Pending" badge. Always pass `"event": "COMMENT"`.

---

## 7. Replying to a prior thread (re-review mode)

Used by the re-review pipeline (see `references/re-review.md`). Replies attach to the **first comment** of a thread, not to the thread node ID:

```bash
gh api --method POST \
  "repos/$OWNER/$REPO/pulls/$PR_NUM/comments/$FIRST_COMMENT_DATABASE_ID/replies" \
  -f body="$REPLY_TEXT"
```

`$FIRST_COMMENT_DATABASE_ID` is the REST numeric id (the `databaseId` field from GraphQL, same as the `id` shown in `#discussion_r<id>` URLs). The preflight manifest exposes this as `firstCommentDatabaseId` on each prior thread.

The reply lands in the same thread as the original review comment, visible inline at the same `(path, line)`. It does NOT create a new review.

---

## 8. Resolving a thread via GraphQL (re-review mode)

REST does not expose thread-resolution state and does not provide a resolve mutation. Use the GraphQL `resolveReviewThread` mutation:

```bash
gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { id isResolved }
  }
}' -f threadId="$THREAD_ID"
```

`$THREAD_ID` is the GraphQL **node ID** (e.g. `PRRT_kw...`), NOT the databaseId. The preflight manifest exposes this as `threadId` on each prior thread.

**Order replies before resolves.** If you POST a reply and then resolve, the reply is visible in the resolved-thread view. If you resolve first, GitHub still accepts the reply but it lands in a collapsed thread and is easy for the author to miss.

**Race with manual resolution.** If `resolveReviewThread` errors with "Thread is already resolved" (or similar), treat as success — the author may have resolved manually between preflight read and post.
