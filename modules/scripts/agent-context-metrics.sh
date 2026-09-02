#!/usr/bin/env bash
# Emit agent-context health and cost metrics as one JSON object per line.
#
# WHY THIS EXISTS
#
# Every failure in the 2026-09-02 session was a number that nobody was
# watching. Each would have been a single-threshold alert:
#
#   skills_reachable      a group cut took ~/.agents/skills from 72 to 11 and
#                         removed 121 skills carrying 164,619 recorded
#                         invocations. Nothing reported it; it surfaced when a
#                         person tried to run one.
#   plugins_missing       a cache purge left 113 of 115 plugins with a missing
#                         installPath. Sessions broke silently until a manual
#                         plugin reload.
#   links_via_aggregate   every rebuild moved every managed path, because
#                         home.file routes through one derivation whose hash
#                         covers the whole home config. Invisible without
#                         comparing readlink across generations.
#   session_tokens        a repo's startup cost doubled between two days with
#                         no single obvious cause.
#
# Output is newline-delimited JSON, one object per metric, ready for a Splunk
# HEC `event` payload, a Grafana/Prometheus textfile exporter, or `jq`.
#
# Usage:
#   agent-context-metrics.sh                 # health only, seconds, no model calls
#   agent-context-metrics.sh --with-tokens R # also measure session cost in repo R
#
# Health metrics make no model calls and are safe to run on a timer. Token
# measurement starts real sessions, so it is opt-in and belongs on a slower
# cadence.
set -uo pipefail

HOSTNAME_S="$(hostname -s 2>/dev/null || echo unknown)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

emit() { # metric value [extra-json]
  printf '{"time":"%s","host":"%s","metric":"%s","value":%s%s}\n' \
    "$TS" "$HOSTNAME_S" "$1" "$2" "${3:-}"
}

# --- reachability, per harness -------------------------------------------
# A harness that reads a tree with a collapsed skill count has lost
# capability, whether or not anyone has noticed yet.
count_tree() {
  [ -d "$1" ] || {
    echo 0
    return
  }
  find -L "$1" -maxdepth 1 -mindepth 1 \( -type d -o -type l \) 2>/dev/null |
    grep -vcE '/(INDEX\.md|GROUPS\.json)$'
}

while IFS='|' read -r harness tree; do
  [ -n "$harness" ] || continue
  emit skills_reachable "$(count_tree "${tree/#\~/$HOME}")" ",\"harness\":\"$harness\""
done <<EOF
claude|$HOME/.claude/skills
codex|$HOME/.agents/skills
cursor|$HOME/.agents/skills
opencode|$HOME/.agents/skills
qwen|$HOME/.qwen/skills
antigravity|$HOME/.gemini/antigravity/skills
EOF

# Catalogue size, so a drop in the deployed count is comparable against what
# the catalogue says SHOULD be deployable.
if [ -r "$HOME/.agents/skills/GROUPS.json" ]; then
  emit skills_in_catalog "$(python3 -c "
import json,sys
try:
    g=json.load(open('$HOME/.agents/skills/GROUPS.json'))
    s=set()
    for v in g.values(): s.update(v.keys() if isinstance(v,dict) else v)
    print(len(s))
except Exception: print(0)
")"
fi

# --- plugin cache health --------------------------------------------------
# A missing installPath means the skill, its hooks and its agents are gone
# from every session that resolved them at startup.
if [ -r "$HOME/.claude/plugins/installed_plugins.json" ]; then
  python3 - "$TS" "$HOSTNAME_S" <<'PY'
import json, os, sys
ts, host = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(os.path.expanduser('~/.claude/plugins/installed_plugins.json')))
except Exception:
    sys.exit(0)
total = missing = 0
for _, entries in d.get('plugins', {}).items():
    for e in entries:
        total += 1
        if not os.path.exists(e.get('installPath', '')):
            missing += 1
for metric, value in (('plugins_installed', total), ('plugins_missing', missing)):
    print(f'{{"time":"{ts}","host":"{host}","metric":"{metric}","value":{value}}}')
PY
fi

# --- rebuild churn --------------------------------------------------------
# Any link resolving through *-home-manager-files/* moves on EVERY rebuild,
# whether or not its content changed. INDEX.md and GROUPS.json are delivered
# that way on purpose and are excluded.
count_aggregate() {
  local n=0 l t
  [ -d "$1" ] || {
    echo 0
    return
  }
  for l in "$1"/*; do
    [ -L "$l" ] || continue
    case "$l" in */INDEX.md | */GROUPS.json) continue ;; esac
    t="$(readlink "$l")"
    case "$t" in *-home-manager-files/*) n=$((n + 1)) ;; esac
  done
  echo "$n"
}

emit links_via_aggregate "$(count_aggregate "$HOME/.claude/plugins/marketplaces")" ',"tree":"marketplaces"'
emit links_via_aggregate "$(count_aggregate "$HOME/.agents/skills")" ',"tree":"agents-skills"'

# A harness ROOT that is itself an aggregate symlink churns even when the tree
# behind it is stable — the qwen and antigravity roots are exactly this shape.
for root in "$HOME/.qwen/skills" "$HOME/.gemini/antigravity/skills" \
  "$HOME/.gemini/antigravity-cli/skills" "$HOME/.claude/skills"; do
  [ -L "$root" ] || continue
  case "$(readlink "$root")" in
    *-home-manager-files/*) v=1 ;;
    *) v=0 ;;
  esac
  emit root_via_aggregate "$v" ",\"root\":\"${root/#$HOME/~}\""
done

# --- session cost (opt-in: starts real sessions) --------------------------
# --strict-mcp-config is mandatory. A bare `claude -p` attaches claude.ai
# hosted MCP connectors nondeterministically and swings the total by up to 25k
# with no config change, which makes runs incomparable.
if [ "${1:-}" = "--with-tokens" ]; then
  shift
  for repo in "$@"; do
    [ -d "$repo" ] || continue
    tok=$(cd "$repo" && claude -p "reply OK" --output-format json \
      --strict-mcp-config 2>/dev/null | python3 -c "
import json,sys
try:
    u=json.load(sys.stdin).get('usage',{})
    print(u.get('input_tokens',0)+u.get('cache_read_input_tokens',0)+u.get('cache_creation_input_tokens',0))
except Exception: print(0)
")
    emit session_tokens "${tok:-0}" ",\"repo\":\"$(basename "$repo")\",\"mcp\":\"none\""
  done
fi
