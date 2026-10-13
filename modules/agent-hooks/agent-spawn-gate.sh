#!/usr/bin/env bash
# Claude Code PreToolUse hook. Applies the agent roster and names the selected
# executor when implementation work should leave the Claude subagent path.
set -euo pipefail

input="$(cat)"
case "$(jq -r '.tool_name // ""' <<<"$input")" in
  Agent | Task) ;;
  *) exit 0 ;;
esac

agents_dir="${CLAUDE_AGENTS_DIR:-$HOME/.claude/agents}"
route_cmd="${AGENT_ROUTE_CMD:-agent-route}"

field() { jq -r --arg k "$1" '.tool_input[$k] // ""' <<<"$input"; }
type="$(field subagent_type)"
model="$(field model)"
effort="$(field effort)"
text="$(jq -r '[.tool_input.description, .tool_input.prompt] | map(. // "") | join("\n")' <<<"$input")"

# Forks inherit the parent's model and effort.
[ "$type" = fork ] && exit 0

repo=""
cwd="$(jq -r '.cwd // .tool_input.cwd // ""' <<<"$input")"
cwd="${cwd:-${CLAUDE_PROJECT_DIR:-}}"
if [ -n "$cwd" ]; then
  remote="$(git -C "$cwd" remote get-url origin 2>/dev/null || true)"
  case "$remote" in
    git@github.com:*) remote="${remote#git@github.com:}" ;;
    ssh://git@github.com/*) remote="${remote#ssh://git@github.com/}" ;;
    https://github.com/*) remote="${remote#https://github.com/}" ;;
    http://github.com/*) remote="${remote#http://github.com/}" ;;
    *) remote="" ;;
  esac
  remote="${remote%.git}"
  if [[ $remote =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$ ]]; then
    repo="$remote"
  fi
fi

# Fill gaps from the agent definition's frontmatter.
def="$agents_dir/${type}.md"
if [ -n "$type" ] && [ -f "$def" ]; then
  front="$(awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f' "$def")"
  [ -z "$model" ] && model="$(sed -n 's/^model:[[:space:]]*//p' <<<"$front" | head -1)"
  [ -z "$effort" ] && effort="$(sed -n 's/^effort:[[:space:]]*//p' <<<"$front" | head -1)"
fi

lc="$(tr '[:upper:]' '[:lower:]' <<<"$text")"
scout_re='read-only|readonly|\bscout|\bexplore\b|\blocate\b|\binventory\b|bulk read|summari[sz]e'
impl_re='\bimplement|\brefactor|\bedit (the|this|these)|\bwrite (the )?code|\bapply (the )?(fix|change|patch)|\bcommit\b|open (a |the )?pr\b'
private_re='secret|credential|private|live[- ]infra|production'

route_kind() {
  if grep -Eq "$private_re" <<<"$lc" || [ -z "$repo" ]; then
    printf '%s\n' private
  else
    printf '%s\n' code-review
  fi
}

route_executor() {
  local kind
  kind="$(route_kind)"
  if [ -n "$repo" ]; then
    "$route_cmd" "$kind" "$repo" 2>/dev/null || printf '%s\n' stop
  else
    "$route_cmd" "$kind" 2>/dev/null || printf '%s\n' stop
  fi
}

deny() {
  local reason route
  reason="$1"
  route="$(route_executor)"
  if [ "$route" = stop ]; then
    reason+=" Automatic route: stop and notify the operator."
  else
    reason+=" Routed alternative: $route."
  fi
  jq -n --arg r "agent-spawn-gate: $reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

case "$model" in
  "") deny "no model. Use subagent_type haiku-high or opus-high, or pass model haiku|opus." ;;
  *haiku*) family=haiku ;;
  *opus*) family=opus ;;
  *) deny "model '$model' is not on the roster (haiku-high, opus-high). Use haiku-high." ;;
esac

case "$effort" in
  high | xhigh | max) ;;
  "") deny "no effort. Pass effort xhigh (haiku) or high (opus), or use a roster agent." ;;
  *) deny "effort '$effort' is below high. Use high, xhigh or max." ;;
esac

if [ "$family" = opus ] && { [ "$type" = Explore ] || grep -Eq "$scout_re" <<<"$lc"; }; then
  deny "read-only scouting goes to haiku-high, not Opus."
fi

if grep -Eq "$impl_re" <<<"$lc" && ! grep -Eq "$scout_re" <<<"$lc" &&
  ! grep -q '\[codex-fallback\]' <<<"$lc"; then
  route="$(route_executor)"
  case "$route" in
    codex | zcode | zcode-flash | opencode-go)
      deny "implementation work is routed to $route by agent-route."
      ;;
    stop)
      deny "no eligible implementation route is available."
      ;;
    haiku-high)
      [ "$family" = haiku ] || deny "implementation work is routed to haiku-high by agent-route."
      ;;
  esac
fi

exit 0
