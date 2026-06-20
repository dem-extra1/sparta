#!/usr/bin/env bash
# Upsert a marker-tagged comment on a PR: PATCH the existing comment that carries
# the marker if one is found, else POST a new one. Keeping this in one place lets
# the demo-video workflow's two comment-posting paths (the recorded-clip path and
# the "no clip applies" note) share a single implementation, so a future change
# to the upsert approach (endpoint, marker matching, pagination) only happens once.
#
# Usage:
#   tools/ci/upsert-pr-comment.sh <repo> <pr-number> <marker> <body> [label]
#
#   <repo>       owner/name (e.g. lacaedemon/sparta)
#   <pr-number>  PR/issue number to comment on
#   <marker>     HTML-comment marker that identifies our comment slot
#   <body>       full comment body (may be multiline; must contain <marker>)
#   [label]      optional noun used in the log line (default: "comment")
#
# Requires the `gh` CLI authenticated via GH_TOKEN in the environment.
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: $(basename "$0") <repo> <pr-number> <marker> <body> [label]" >&2
  exit 1
fi

REPO="$1"
PR="$2"
MARKER="$3"
BODY="$4"
LABEL="${5:-comment}"

# Find our existing comment by its marker. The marker is passed to jq via --arg
# (not interpolated into the filter) so a marker containing quotes can't break the
# filter. `|| true` so "no match" (and the resulting non-zero from the pipeline)
# doesn't trip `set -e`.
CID=$(gh api "repos/${REPO}/issues/${PR}/comments" --paginate \
  | jq --raw-output --arg marker "$MARKER" \
      '.[] | select(.body | contains($marker)) | .id' \
  | head -n1 || true)

if [ -n "$CID" ]; then
  gh api -X PATCH "repos/${REPO}/issues/comments/${CID}" -f body="$BODY" >/dev/null
  echo "Updated ${LABEL} (id ${CID})"
else
  gh api -X POST "repos/${REPO}/issues/${PR}/comments" -f body="$BODY" >/dev/null
  echo "Posted new ${LABEL}"
fi
