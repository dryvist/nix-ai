#!/usr/bin/env bash
# Test body for the agent-spawn-gate check (lib/checks/lint.nix).
# Runs modules/agent-hooks/agent-spawn-gate.sh directly against Agent
# PreToolUse inputs, asserting each case allows (empty stdout) or denies
# (deny JSON). CODEX_QUOTA_CMD stands in for codex-quota: `true` = Codex has
# quota, `false` = exhausted.
set -euo pipefail

out="${out:?out not set (expected from the Nix build environment)}"
script="${SRC}/modules/agent-hooks/agent-spawn-gate.sh"

agents="$(mktemp -d)"
printf -- '---\nname: haiku-high\nmodel: haiku\neffort: xhigh\n---\n' >"$agents/haiku-high.md"
printf -- '---\nname: opus-high\nmodel: opus\neffort: high\n---\n' >"$agents/opus-high.md"

fail=0

spawn() {
  jq -nc --arg t "$1" --arg m "$2" --arg e "$3" --arg p "$4" \
    '{tool_name: "Agent", tool_input: ({subagent_type: $t, model: $m, effort: $e, prompt: $p, description: "d"} | with_entries(select(.value != "")))}'
}

check() {
  local want="$1" quota="$2" label="$3" input="$4" result
  result=$(printf '%s' "$input" | CLAUDE_AGENTS_DIR="$agents" CODEX_QUOTA_CMD="$quota" bash "$script")
  if [ "$want" = allow ] && [ -n "$result" ]; then
    echo "FAIL ($label): expected allow, got: $result" >&2
    fail=1
  elif [ "$want" = deny ] && ! printf '%s' "$result" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; then
    echo "FAIL ($label): expected a deny decision, got: $result" >&2
    fail=1
  else
    echo "PASS ($label): $want"
  fi
}

check allow false "non-Agent tool" '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
check allow false "haiku-high roster agent" "$(spawn haiku-high '' '' 'scan the repo')"
check allow false "opus-high design" "$(spawn opus-high '' '' 'design the hook architecture')"
check allow false "fork inherits" "$(spawn fork '' '' 'anything')"
check allow false "explicit haiku xhigh scout" "$(spawn general-purpose haiku xhigh 'read-only scout of the repo')"
check deny false "sonnet" "$(spawn general-purpose sonnet high 'scan')"
check deny false "fable subagent" "$(spawn general-purpose fable high 'plan')"
check deny false "no model" "$(spawn general-purpose '' '' 'scan')"
check deny false "effort medium" "$(spawn general-purpose haiku medium 'scan')"
check deny false "roster agent effort low" "$(spawn haiku-high '' low 'scan')"
check deny false "no effort" "$(spawn general-purpose haiku '' 'scan')"
check deny false "opus scout prompt" "$(spawn opus-high '' '' 'read-only scout of the repo')"
check deny false "opus Explore" "$(spawn Explore opus high 'find the hook')"
check deny true "implementation while Codex has quota" "$(spawn haiku-high '' '' 'implement the gate')"
check allow false "implementation when Codex exhausted" "$(spawn haiku-high '' '' 'implement the gate')"
check allow true "codex-fallback marker" "$(spawn haiku-high '' '' '[codex-fallback] implement the gate')"
check allow true "read-only summary with quota" "$(spawn haiku-high '' '' 'read-only: summarize how commits flow')"

rm -rf "$agents"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "agent-spawn-gate: all cases behave as expected"
touch "$out"
