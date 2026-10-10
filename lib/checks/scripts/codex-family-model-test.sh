#!/usr/bin/env bash
# Usage: codex-family-model-test.sh <path to codex-family-model.sh>
# Fixture slugs carry no version on purpose: the script must rank by `priority` alone.
set -euo pipefail

script=$1
root=$(mktemp -d)

write_cache() {
  cat > "$root/models_cache.json" <<'JSON'
{"models":[
  {"slug":"gpt-older-luna","visibility":"list","priority":9},
  {"slug":"gpt-newer-luna","visibility":"list","priority":4},
  {"slug":"gpt-newest-sol","visibility":"list","priority":1},
  {"slug":"gpt-hidden-luna","visibility":"hide","priority":0}
]}
JSON
}
write_config() {
  printf 'model = "stale"\nmodel_reasoning_effort = "xhigh"\n\n[mcp_servers.demo]\ncommand = "demo"\n' > "$root/config.toml"
}
expect() { # <label> <jq filter> <expected>
  actual=$(yj -tj < "$root/config.toml" | jq -r "$2")
  [[ "$actual" == "$3" ]] || { echo "FAIL $1: got '$actual', want '$3'" >&2; exit 1; }
}

write_cache; write_config
"$script" luna "$root"
expect "lowest priority wins" .model gpt-newer-luna
expect "other keys kept" .model_reasoning_effort xhigh
expect "tables kept" .mcp_servers.demo.command demo

write_config
"$script" sol "$root"
expect "other family" .model gpt-newest-sol

write_config
"$script" absent "$root"
expect "unknown family leaves model" .model stale

write_config; rm "$root/models_cache.json"
"$script" luna "$root"
expect "missing cache leaves model" .model stale
echo "codex-family-model: all cases passed"
