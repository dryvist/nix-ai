#!/usr/bin/env bash
# Pushes Prometheus exposition from one or more readers to an import endpoint.
#
# usage: agent-quota-push READER...
#   Each READER is an executable that prints exposition on stdout and exits
#   non-zero when it has no reading. Every reader must succeed. If any fails,
#   nothing is pushed, including the output of readers that did succeed.
# Environment:
#   AGENT_QUOTA_WRITE_URL         import endpoint the exposition is POSTed to
#   AGENT_QUOTA_WRITE_TOKEN_FILE  file holding the bearer token. curl reads the
#                                 file itself, so the token is never in argv,
#                                 a log or a copy.
# A run logs one line. The request body is never logged.
set -euo pipefail

: "${AGENT_QUOTA_WRITE_URL:?AGENT_QUOTA_WRITE_URL is not set}"
: "${AGENT_QUOTA_WRITE_TOKEN_FILE:?AGENT_QUOTA_WRITE_TOKEN_FILE is not set}"
if [ "$#" -eq 0 ]; then
  echo "agent-quota-push: no readers given; nothing pushed" >&2
  exit 1
fi

body=""
for reader in "$@"; do
  if ! out="$("$reader")"; then
    echo "agent-quota-push: nothing pushed; reader ${reader##*/} failed" >&2
    exit 1
  fi
  body+="$out"$'\n'
done

series="$(printf '%s' "$body" | grep -cE '^[A-Za-z_:]' || true)"
if [ "$series" -eq 0 ]; then
  echo "agent-quota-push: nothing pushed; readers produced no series" >&2
  exit 1
fi

# {{token:trim}} drops any trailing newline the token file carries before the header is built.
if ! reason="$(printf '%s' "$body" | curl --fail --silent --show-error --max-time 20 \
  --variable "token@${AGENT_QUOTA_WRITE_TOKEN_FILE}" \
  --expand-header 'Authorization: Bearer {{token:trim}}' \
  --header 'Content-Type: text/plain' \
  --data-binary @- \
  "$AGENT_QUOTA_WRITE_URL" 2>&1 >/dev/null)"; then
  echo "agent-quota-push: push failed, $series series not accepted: $reason" >&2
  exit 1
fi
echo "agent-quota-push: pushed $series series"
