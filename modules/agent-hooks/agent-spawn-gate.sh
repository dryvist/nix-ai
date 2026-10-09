#!/usr/bin/env bash
# Claude Code PreToolUse hook. Denies subagent spawns that break the
# delegation policy: roster is haiku + opus only, effort never below high,
# no Opus on read-only scouting, no Claude implementation while Codex has quota.
# Every other tool passes through untouched.
set -euo pipefail

input="$(cat)"
case "$(jq -r '.tool_name // ""' <<<"$input")" in
  Agent | Task) ;;
  *) exit 0 ;;
esac

agents_dir="${CLAUDE_AGENTS_DIR:-$HOME/.claude/agents}"
quota_cmd="${CODEX_QUOTA_CMD:-codex-quota}"

deny() {
  jq -n --arg r "agent-spawn-gate: $1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

field() { jq -r --arg k "$1" '.tool_input[$k] // ""' <<<"$input"; }
type="$(field subagent_type)"
model="$(field model)"
effort="$(field effort)"
text="$(jq -r '[.tool_input.description, .tool_input.prompt] | map(. // "") | join("\n")' <<<"$input")"

# Forks inherit the parent's model and effort.
[ "$type" = "fork" ] && exit 0

# Fill gaps from the agent definition's frontmatter.
def="$agents_dir/${type}.md"
if [ -n "$type" ] && [ -f "$def" ]; then
  front="$(awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {exit} f' "$def")"
  [ -z "$model" ] && model="$(sed -n 's/^model:[[:space:]]*//p' <<<"$front" | head -1)"
  [ -z "$effort" ] && effort="$(sed -n 's/^effort:[[:space:]]*//p' <<<"$front" | head -1)"
fi

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

lc="$(tr '[:upper:]' '[:lower:]' <<<"$text")"
scout_re='read-only|readonly|\bscout|\bexplore\b|\blocate\b|\binventory\b|bulk read|summari[sz]e'
impl_re='\bimplement|\brefactor|\bedit (the|this|these)|\bwrite (the )?code|\bapply (the )?(fix|change|patch)|\bcommit\b|open (a |the )?pr\b'

if [ "$family" = opus ] && { [ "$type" = "Explore" ] || grep -Eq "$scout_re" <<<"$lc"; }; then
  deny "read-only scouting goes to haiku-high, not Opus."
fi

if grep -Eq "$impl_re" <<<"$lc" && ! grep -Eq "$scout_re" <<<"$lc" &&
  ! grep -q '\[codex-fallback\]' <<<"$lc" && "$quota_cmd" >/dev/null 2>&1; then
  deny "Codex has quota; implementation goes to Codex first: cd ~/git && codex exec -s danger-full-access -c model_reasoning_effort='\"xhigh\"' --skip-git-repo-check -C <repo> -o <out> - < prompt.md (background). If Codex fails, retry this spawn with [codex-fallback] in the prompt."
fi

exit 0
