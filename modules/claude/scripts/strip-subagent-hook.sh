#!/usr/bin/env bash
# Strip ponytail's SubagentStart hook from its own hooks/claude-codex-hooks.json.
#
# ponytail injects ~5KB into EVERY subagent spawn, including read-only
# Explore/Plan agents that write no code — the same guidance already ships as
# the ponytail skill, so a code-writing session can still pull it in on
# purpose. ponytail is a native `.claude-plugin/` marketplace with no
# nix-claude-code synthetic wrapper (see modules/claude/marketplaces.nix), so
# this is the one place its content is nix-materialized and therefore
# patchable at build time, without maintaining a fork of the plugin.
#
# $1 = source ponytail tree, $2 = output path.
set -euo pipefail

src="$1"
out="$2"
hooks_file="hooks/claude-codex-hooks.json"

cp -RL "$src" "$out"
chmod -R u+w "$out"

if [ ! -f "$out/$hooks_file" ]; then
  echo "strip-subagent-hook: expected $hooks_file in ponytail source, not found" >&2
  exit 1
fi

if ! jq -e '.hooks.SubagentStart' "$out/$hooks_file" > /dev/null; then
  echo "strip-subagent-hook: ponytail no longer declares a SubagentStart hook — drop this patch" >&2
  exit 1
fi

jq 'del(.hooks.SubagentStart)' "$out/$hooks_file" > "$out/$hooks_file.tmp"
mv "$out/$hooks_file.tmp" "$out/$hooks_file"
