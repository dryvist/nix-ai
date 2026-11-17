#!/usr/bin/env bash
# Resolve the OpenAI model selection from Codex's cache under AGENTS.md, "Delegation routing".
# Codex accepts exact model slugs, so the cache ranks them by `priority`, and the lowest is newest.
#
# Writes the configured Luna model and xhigh effort to config.toml.
#
# Arguments:
#   $1 - model family
#   $2 - reasoning effort
#   $3 - Codex directory holding models_cache.json and config.toml
#
# jq and yj must be on PATH (callers ensure this via PATH export).

set -euo pipefail

family="$1"
reasoning_effort="$2"
dir="$3"
cache="$dir/models_cache.json"
target="$dir/config.toml"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] codex-family-model: $2" >&2; }

if [[ "$family" != "luna" || "$reasoning_effort" != "xhigh" ]]; then
  log ERROR 'OpenAI Codex selection follows AGENTS.md, "Delegation routing"'
  exit 2
fi

slug=""
if [[ -f "$cache" ]]; then
  slug=$(jq -r --arg f "$family" \
    '[.models[]? | select(.visibility == "list" and (.slug | endswith("-" + $f)))] | sort_by(.priority // 1000000) | .[0].slug // empty' \
    "$cache" 2>/dev/null) || slug=""
fi
if [[ -z "$slug" ]]; then
  log WARN "no listed $family model in $cache; leaving model unchanged"
  exit 0
fi
if [[ ! -f "$target" || -L "$target" ]]; then
  log WARN "$target is not a regular file; leaving it unchanged"
  exit 0
fi

tmp=$(mktemp "$target.XXXXXX")
trap 'rm -f "$tmp"' EXIT
yj -tj < "$target" | jq --arg m "$slug" --arg e "$reasoning_effort" '.model = $m | .model_reasoning_effort = $e' | yj -jt > "$tmp"
chmod 600 "$tmp"
mv "$tmp" "$target"
trap - EXIT
log INFO "model set to $slug"
