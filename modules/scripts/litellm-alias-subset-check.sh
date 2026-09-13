#!/usr/bin/env bash
# CI-time counterpart to the pure litellm-alias-list-consistency check
# (lib/checks/litellm-local-aliases.nix). That check proves nix-ai's own
# consumers render exactly modules/litellm-local/aliases.nix; it cannot prove
# the router itself actually serves every name in that list, because a pure
# Nix evaluation has no network access.
#
# Asserts LITELLM_ALIASES (the committed list, space-separated) is a SUBSET
# of the router's live `/v1/models`. Never asserts equality: the router is
# free to serve more model groups (physical ids, legacy synonyms) than the
# capability aliases this repo names.
#
# MUST SKIP CLEANLY, NEVER SILENTLY PASS, when no router credentials are in
# the environment — a CI job that runs on every PR (including forks with no
# secrets) must not report green for a check it never ran.
set -euo pipefail

BASE="${ROUTER_BASE_URL:-}"
KEY="${ROUTER_API_KEY:-}"

if [ -z "$BASE" ] || [ -z "$KEY" ]; then
  echo "skipped: no router credentials (set ROUTER_BASE_URL + ROUTER_API_KEY)"
  exit 0
fi

if [ "$#" -eq 0 ]; then
  echo "usage: ${0##*/} ALIAS [ALIAS ...]" >&2
  echo "   or: set LITELLM_ALIASES to a space-separated list" >&2
  # shellcheck disable=SC2086
  set -- ${LITELLM_ALIASES:-}
fi

if [ "$#" -eq 0 ]; then
  echo "no aliases given (pass as args or set LITELLM_ALIASES)" >&2
  exit 2
fi

response=$(curl -sS -m 30 "$BASE/v1/models" -H "Authorization: Bearer $KEY")
served=$(printf '%s' "$response" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for m in d.get("data", []):
    print(m.get("id", ""))
')

missing=()
for alias in "$@"; do
  if ! grep -qxF "$alias" <<<"$served"; then
    missing+=("$alias")
  fi
done

if [ "${#missing[@]}" -ne 0 ]; then
  echo "router does not serve: ${missing[*]}" >&2
  echo "committed list: modules/litellm-local/aliases.nix" >&2
  exit 1
fi

echo "router serves all $# committed alias(es)"
