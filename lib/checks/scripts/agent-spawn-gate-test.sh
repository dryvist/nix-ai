#!/usr/bin/env bash
set -euo pipefail

out="${out:?out not set (expected from the Nix build environment)}"
script="${SRC}/modules/agent-hooks/agent-spawn-gate.sh"
agents="$(mktemp -d)"
tmp="$(mktemp -d)"
trap 'rm -rf "$agents" "$tmp"' EXIT
printf -- '---\nname: haiku-high\nmodel: haiku\neffort: xhigh\n---\n' >"$agents/haiku-high.md"
printf -- '---\nname: opus-high\nmodel: opus\neffort: high\n---\n' >"$agents/opus-high.md"
cat >"$tmp/agent-route" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >>"$TEST_ROUTE_LOG"
printf '%s\n' "${TEST_ROUTE:-codex}"
EOF
chmod +x "$tmp/agent-route"
export AGENT_ROUTE_CMD="$tmp/agent-route"
export TEST_ROUTE_LOG="$tmp/route.log"

fail=0

spawn() {
  jq -nc --arg t "$1" --arg m "$2" --arg e "$3" --arg p "$4" \
    '{tool_name: "Agent", cwd: "/tmp/repo", tool_input: ({subagent_type: $t, model: $m, effort: $e, prompt: $p, description: "d"} | with_entries(select(.value != "")))}'
}

check() {
  local want="$1" route="$2" label="$3" input="$4" result
  result="$(printf '%s' "$input" | CLAUDE_AGENTS_DIR="$agents" TEST_ROUTE="$route" bash "$script")"
  if [ "$want" = allow ] && [ -n "$result" ]; then
    printf 'FAIL (%s): expected allow, got: %s\n' "$label" "$result" >&2
    fail=1
  elif [ "$want" = deny ] && ! jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$result" >/dev/null; then
    printf 'FAIL (%s): expected a deny decision, got: %s\n' "$label" "$result" >&2
    fail=1
  elif [ "$want" = deny ] && ! jq -e --arg route "$route" \
    '.hookSpecificOutput.permissionDecisionReason | contains("Routed alternative: " + $route + ".")' \
    <<<"$result" >/dev/null; then
    printf 'FAIL (%s): deny reason did not name the route: %s\n' "$label" "$result" >&2
    fail=1
  else
    printf 'PASS (%s): %s\n' "$label" "$want"
  fi
}

check allow codex "non-Agent tool" '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
check allow codex "haiku-high roster agent" "$(spawn haiku-high '' '' 'scan the repo')"
check allow codex "opus-high design" "$(spawn opus-high '' '' 'design the hook architecture')"
check allow codex "fork inherits" "$(spawn fork '' '' 'anything')"
check allow codex "explicit haiku xhigh scout" "$(spawn general-purpose haiku xhigh 'read-only scout of the repo')"
check deny codex "sonnet" "$(spawn general-purpose sonnet high 'scan')"
check deny codex "fable subagent" "$(spawn general-purpose fable high 'plan')"
check deny codex "no model" "$(spawn general-purpose '' '' 'scan')"
check deny codex "effort medium" "$(spawn general-purpose haiku medium 'scan')"
check deny codex "roster agent effort low" "$(spawn haiku-high '' low 'scan')"
check deny codex "no effort" "$(spawn general-purpose haiku '' 'scan')"
check deny codex "opus scout prompt" "$(spawn opus-high '' '' 'read-only scout of the repo')"
check deny codex "opus Explore" "$(spawn Explore opus high 'find the hook')"
check deny codex "implementation routes to Codex" "$(spawn haiku-high '' '' 'implement the gate')"
check deny zcode "implementation routes to ZCode" "$(spawn haiku-high '' '' 'implement the gate')"
check allow haiku-high "implementation reaches haiku" "$(spawn haiku-high '' '' 'implement the gate')"
check allow codex "codex fallback marker" "$(spawn haiku-high '' '' '[codex-fallback] implement the gate')"
check allow codex "read-only summary" "$(spawn haiku-high '' '' 'read-only: summarize how commits flow')"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
printf '%s\n' 'agent-spawn-gate: all cases behave as expected'
touch "$out"
