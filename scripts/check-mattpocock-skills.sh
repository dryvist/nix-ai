#!/usr/bin/env bash
set -euo pipefail

upstream="$1"
default_config="$2"
grouped_config="$3"
marking_scripts="$4"

bash "$marking_scripts/mark-manual-invoke.sh" "$upstream" marked
bash "$marking_scripts/mark-installed-cache.sh" marked
for path in $SKILL_PATHS; do
  cmp "$upstream/$path/SKILL.md" "marked/$path/SKILL.md"
  cmp "$upstream/$path/agents/openai.yaml" "marked/$path/agents/openai.yaml"
done

for name in $MANUAL_NAMES; do
  jq -e --arg name "$name" '
    .permission.skill[$name] == "deny" and
    (.command[$name].template | contains("@/home/test-user/.codex/skills/" + $name + "/SKILL.md")) and
    (.command[$name].template | contains("$ARGUMENTS"))
  ' "$default_config" >/dev/null
done
for name in $MODEL_NAMES; do
  jq -e --arg name "$name" '
    (.permission.skill[$name] // "allow") == "allow" and
    (.command | has($name) | not)
  ' "$default_config" >/dev/null
done

for name in $PRODUCTIVITY_MANUAL_NAMES; do
  jq -e --arg name "$name" '
    .permission.skill[$name] == "deny" and
    (.command[$name].template | contains("@/home/test-user/.agents/skills/" + $name + "/SKILL.md"))
  ' "$grouped_config" >/dev/null
done
jq -e '(.command | length) == 5 and (.command | has("implement") | not)' \
  "$grouped_config" >/dev/null
echo 'Matt Pocock: 27 complete skills; 16 manual/11 model; both marking stages and OpenCode policy verified'
