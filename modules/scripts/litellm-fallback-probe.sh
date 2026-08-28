#!/usr/bin/env bash
# Probe every member of the local proxy's cost-ordered fallback chain.
#
# This exists because a chain member can die WITHOUT any config changing.
# On 2026-08-28 the router's `subagent` alias still resolved cleanly in
# `/v1/model/info` while every actual completion returned 404 — the model's
# preview period had ended upstream. Config inspection cannot see that; only a
# real completion can. So this sends one, per member.
#
# Exit 0 only if EVERY member answers. A partial chain is still serving
# traffic, which is exactly why it goes unnoticed until the last rung fails
# too — so a dead member is an error here, not a warning.
set -euo pipefail

BASE="${LITELLM_LOCAL_URL:-http://127.0.0.1:4100}"
TOKEN="${LITELLM_LOCAL_TOKEN:-local}"
# Reasoning models spend output tokens before emitting content; too small a cap
# returns finish_reason=length with empty content and looks like a failure.
MAX_TOKENS="${PROBE_MAX_TOKENS:-200}"
TIMEOUT="${PROBE_TIMEOUT:-120}"

# With no arguments, probe the chain this host is configured to fall through.
# LITELLM_FALLBACK_CHAIN is a space-separated list; splitting it is intentional,
# so word-splitting is enabled for exactly this expansion.
if [ "$#" -eq 0 ]; then
  # shellcheck disable=SC2086
  set -- ${LITELLM_FALLBACK_CHAIN:-}
fi

if [ "$#" -eq 0 ]; then
  echo "usage: ${0##*/} MODEL_NAME [MODEL_NAME ...]" >&2
  echo "   or: set LITELLM_FALLBACK_CHAIN to a space-separated list" >&2
  exit 2
fi

failed=0
for model in "$@"; do
  printf '%-24s ' "$model"

  body=$(printf '{"model":%s,"max_tokens":%s,"messages":[{"role":"user","content":"Reply with exactly: OK"}]}' \
    "$(printf '%s' "$model" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    "$MAX_TOKENS")

  # `|| true` so a curl failure is classified below rather than killing the
  # loop under `set -e` — one dead member must not hide the rest of the chain.
  response=$(curl -sS -m "$TIMEOUT" -X POST "$BASE/v1/chat/completions" \
    -H 'content-type: application/json' \
    -H "Authorization: Bearer $TOKEN" \
    -d "$body" 2>&1) || true

  verdict=$(printf '%s' "$response" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print("FAIL\tunparseable response: " + raw[:160].replace("\n", " "))
    raise SystemExit
if "error" in d:
    print("FAIL\t" + str(d["error"].get("message", d["error"]))[:160].replace("\n", " "))
    raise SystemExit
try:
    choice = d["choices"][0]
except (KeyError, IndexError):
    print("FAIL\tno choices in response")
    raise SystemExit
# A served response is the signal. Content may legitimately be empty when a
# reasoning model spends the whole budget thinking, so finish_reason=length
# with zero content is reported but NOT treated as a dead member.
served = d.get("model") or "?"
fin = choice.get("finish_reason")
content = (choice.get("message") or {}).get("content") or ""
note = "" if content.strip() else "  (empty content, finish_reason=%s)" % fin
print("OK\tserved=%s%s" % (served, note))
')

  status=${verdict%%$'\t'*}
  detail=${verdict#*$'\t'}
  echo "$status  $detail"
  [ "$status" = "OK" ] || failed=$((failed + 1))
done

if [ "$failed" -ne 0 ]; then
  echo "" >&2
  echo "$failed chain member(s) failed. A dead member does not surface on its own —" >&2
  echo "traffic silently shifts to the next rung until the last one goes too." >&2
  echo "Re-rank the chain in modules/litellm-local/fallback-tier.nix." >&2
  exit 1
fi

echo ""
echo "all $# chain member(s) served a completion"
