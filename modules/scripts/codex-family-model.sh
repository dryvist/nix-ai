#!/usr/bin/env bash
# Point config.toml's `model` at the listed model of a family (for example "luna") that Codex's own model cache
# ranks newest. Codex accepts exact model slugs only, so the slug is resolved here, at activation, and no version
# is written in Nix or parsed here: the cache ranks models by `priority`, and the lowest is the newest.
#
# Edits only the `model` key, in place. Nothing else in config.toml is touched.
#
# Arguments:
#   $1 - model family, the slug suffix after the last dash (for example luna)
#   $2 - Codex directory holding models_cache.json and config.toml
#
# jq and yj must be on PATH (callers ensure this via PATH export).

set -euo pipefail

family="$1"
dir="$2"
cache="$dir/models_cache.json"
target="$dir/config.toml"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] codex-family-model: $2" >&2; }

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
yj -tj < "$target" | jq --arg m "$slug" '.model = $m' | yj -jt > "$tmp"
chmod 600 "$tmp"
mv "$tmp" "$target"
trap - EXIT
log INFO "model set to $slug"
