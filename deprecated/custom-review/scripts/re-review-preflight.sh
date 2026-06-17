#!/usr/bin/env bash
# re-review-preflight.sh — read-side work for /custom-review re-review mode.
#
# Emits a manifest JSON to /tmp/custom-review-preflight-<PR_NUM>.json describing:
#   - mode (skip | round-1 | re-review)
#   - round number, last marker SHA, force-push status, delta scope
#   - prior review threads owned by this skill (with severity/bucket parsed from first comment)
#
# Inputs: OWNER REPO PR_NUM HEAD_SHA SELF_LOGIN
# Exit codes: 0 on success (read manifest at the printed path), non-zero on hard failure.

set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 OWNER REPO PR_NUM HEAD_SHA SELF_LOGIN" >&2
  exit 64
fi

OWNER="$1"
REPO="$2"
PR_NUM="$3"
HEAD_SHA="$4"
SELF_LOGIN="$5"

OUT="/tmp/custom-review-preflight-${PR_NUM}.json"

# --- 1. Fetch reviews; filter to ours (marker in body AND author == SELF_LOGIN) ---
# Reviews are sorted oldest → newest by submittedAt.
REVIEWS_JSON=$(gh api "repos/${OWNER}/${REPO}/pulls/${PR_NUM}/reviews" --paginate)

# Our reviews: body contains "<!-- custom-review:" AND author.login == SELF_LOGIN.
# Extract marker SHA from body via sed.
OUR_REVIEWS=$(echo "$REVIEWS_JSON" | jq --arg me "$SELF_LOGIN" '
  [ .[]
    | select(.user.login == $me)
    | select(.body | test("<!-- custom-review:[0-9a-f]+ -->"))
    | {
        body: .body,
        submittedAt: .submitted_at,
        markerSha: (.body | capture("<!-- custom-review:(?<sha>[0-9a-f]+) -->") | .sha)
      }
  ]
')

PRIOR_COUNT=$(echo "$OUR_REVIEWS" | jq 'length')

# --- 2. Round-1 fast path: no prior matching reviews ---
if [[ "$PRIOR_COUNT" -eq 0 ]]; then
  jq -n --arg head "$HEAD_SHA" '{
    mode: "round-1",
    skipReason: null,
    headSha: $head,
    lastMarkerSha: null,
    roundNumber: 1,
    forcePushDetected: false,
    deltaScope: null,
    priorThreads: []
  }' > "$OUT"
  echo "$OUT"
  exit 0
fi

# --- 3. Re-review or skip-at-head: identify latest review ---
LATEST=$(echo "$OUR_REVIEWS" | jq '.[-1]')
LATEST_MARKER_SHA=$(echo "$LATEST" | jq -r '.markerSha')
LATEST_SUBMITTED_AT=$(echo "$LATEST" | jq -r '.submittedAt')
ROUND_NUMBER=$((PRIOR_COUNT + 1))

# --- 4. GraphQL reviewThreads for the PR ---
THREADS_RAW=$(gh api graphql -f query='
query($owner: String!, $repo: String!, $num: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $num) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 50) {
            nodes {
              databaseId
              author { login }
              createdAt
              body
              pullRequestReview {
                id
                body
                author { login }
                submittedAt
              }
            }
          }
        }
      }
    }
  }
}' -F owner="$OWNER" -F repo="$REPO" -F num="$PR_NUM")

# Filter threads to "ours": first comment's parent review has marker AND login == SELF_LOGIN.
OUR_THREADS=$(echo "$THREADS_RAW" | jq --arg me "$SELF_LOGIN" '
  .data.repository.pullRequest.reviewThreads.nodes
  | map(select(
      (.comments.nodes | length) > 0
      and (.comments.nodes[0].pullRequestReview // null) != null
      and (.comments.nodes[0].pullRequestReview.author.login == $me)
      and (.comments.nodes[0].pullRequestReview.body | test("<!-- custom-review:[0-9a-f]+ -->"))
    ))
')

# --- 5. Reply-only re-fire detection (when marker matches HEAD) ---
# If HEAD == latest marker, check whether any comment on our threads was created
# strictly after the latest review submittedAt (i.e., the author replied since).
if [[ "$LATEST_MARKER_SHA" == "$HEAD_SHA" ]]; then
  NEW_REPLY_COUNT=$(echo "$OUR_THREADS" | jq --arg t "$LATEST_SUBMITTED_AT" '
    [ .[]
      | .comments.nodes[]
      | select(.createdAt > $t)
    ] | length
  ')
  if [[ "$NEW_REPLY_COUNT" -eq 0 ]]; then
    jq -n --arg head "$HEAD_SHA" --arg marker "$LATEST_MARKER_SHA" --argjson round "$ROUND_NUMBER" '{
      mode: "skip",
      skipReason: "already-reviewed-at-head",
      headSha: $head,
      lastMarkerSha: $marker,
      roundNumber: $round,
      forcePushDetected: false,
      deltaScope: null,
      priorThreads: []
    }' > "$OUT"
    echo "$OUT"
    exit 0
  fi
fi

# --- 6. Force-push detection: is latest marker SHA reachable in local git? ---
FORCE_PUSH=false
if ! git cat-file -e "${LATEST_MARKER_SHA}^{commit}" 2>/dev/null; then
  FORCE_PUSH=true
fi

if [[ "$FORCE_PUSH" == "true" ]]; then
  DELTA_SCOPE="full-pr-diff"
elif [[ "$LATEST_MARKER_SHA" == "$HEAD_SHA" ]]; then
  # Reply-only re-fire: no new commits, delta-scan has nothing to find.
  DELTA_SCOPE="${LATEST_MARKER_SHA}..HEAD"
else
  DELTA_SCOPE="${LATEST_MARKER_SHA}..HEAD"
fi

# --- 7. Build prior-thread list with severity/bucket parsed from first comment body ---
# Severity emoji + optional "**Likely intentional?**" bucket framing per references/posting.md § 5.
# Build a map of markerSha -> round number for fromRound tagging.
MARKER_TO_ROUND=$(echo "$OUR_REVIEWS" | jq '
  to_entries | map({key: .value.markerSha, value: (.key + 1)}) | from_entries
')

PRIOR_THREADS=$(echo "$OUR_THREADS" | jq --argjson m2r "$MARKER_TO_ROUND" '
  def parse_first($body):
    {
      severity: (
        if   ($body | startswith("🔴")) then "high"
        elif ($body | startswith("🟡")) then "medium"
        elif ($body | startswith("🔵")) then "nit"
        elif ($body | startswith("❓")) then "question"
        else "unknown"
        end
      ),
      bucket: (
        if ($body | test("\\*\\*Likely intentional\\?\\*\\*")) then "Likely intentional"
        else "Issue"
        end
      )
    };
  def round_for($reviewBody):
    ($reviewBody | capture("<!-- custom-review:(?<sha>[0-9a-f]+) -->") | .sha) as $sha
    | ($m2r[$sha] // null);
  map({
    threadId: .id,
    firstCommentDatabaseId: .comments.nodes[0].databaseId,
    isResolved: .isResolved,
    isOutdated: .isOutdated,
    path: .path,
    line: .line,
    originalSeverity: (parse_first(.comments.nodes[0].body) | .severity),
    originalBucket: (parse_first(.comments.nodes[0].body) | .bucket),
    fromRound: round_for(.comments.nodes[0].pullRequestReview.body),
    comments: [ .comments.nodes[] | {
      author: .author.login,
      createdAt: .createdAt,
      body: .body
    } ]
  })
  | map(select(.isResolved == false))
')

# --- 8. Emit manifest ---
jq -n \
  --arg head "$HEAD_SHA" \
  --arg marker "$LATEST_MARKER_SHA" \
  --argjson round "$ROUND_NUMBER" \
  --argjson force "$FORCE_PUSH" \
  --arg delta "$DELTA_SCOPE" \
  --argjson threads "$PRIOR_THREADS" '{
    mode: "re-review",
    skipReason: null,
    headSha: $head,
    lastMarkerSha: $marker,
    roundNumber: $round,
    forcePushDetected: $force,
    deltaScope: $delta,
    priorThreads: $threads
  }' > "$OUT"

echo "$OUT"
