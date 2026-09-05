# shellcheck shell=bash
# Links the skill groups a repository declares into its own skill trees.
#
#   agent-skill-groups link [repo-root]    create/prune links (quiet, exit 0)
#   agent-skill-groups status [repo-root]  print declared groups and links
#
# Declaration: AGENTS.md frontmatter `skill-groups: [core, homelab]` (flow or
# block list). Source: $HOME/.agents/skills/GROUPS.json, group -> name -> dir.
# Targets: .agents/skills/<name> (Codex, Cursor, OpenCode, Antigravity, qwen)
# and .claude/skills/<name> (Claude Code). Only symlinks into the Nix store are
# ever created or removed; a repository's own skills are never touched.
# `mcp-servers: [zammad]` merges ~/.claude/mcp-available/<name>.json into
# .mcp.json (Claude Code project scope). Nothing is committed: the trees and
# .mcp.json go into .git/info/exclude.

cmd="${1:-link}"
root="${2:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
groups_file="${AGENT_SKILL_GROUPS_FILE:-$HOME/.agents/skills/GROUPS.json}"
trees=(.agents/skills .claude/skills)

[ -n "$root" ] && [ -f "$root/AGENTS.md" ] || exit 0
[ -f "$groups_file" ] || {
  echo "agent-skill-groups: no $groups_file" >&2
  exit 0
}
cd "$root" || exit 0

# Frontmatter list value of one key, one name per line.
frontmatter_list() {
  awk -v key="$1" '
  NR==1 && $0!="---" { exit }
  NR>1 && $0=="---" { exit }
  index($0, key ":")==1 {
    v=$0; sub("^" key ":[ \t]*", "", v)
    if (v ~ /^\[/) {
      gsub(/[\[\]]/, "", v); n=split(v, a, /[ \t]*,[ \t]*/)
      for (i=1;i<=n;i++) if (a[i]!="") print a[i]
      exit
    }
    inlist=1; next
  }
  inlist && /^[ \t]*-[ \t]+/ { s=$0; sub(/^[ \t]*-[ \t]+/, "", s); print s; next }
  inlist { exit }
' AGENTS.md | tr -d "\"'"
}
declared="$(frontmatter_list skill-groups)"

# .mcp.json is rewritten on every run; a tracked one is never touched.
mcp_avail="${AGENT_MCP_CLAUDE_DIR:-$HOME/.claude/mcp-available}"
mcp_frags=()
for s in $(frontmatter_list mcp-servers); do
  [ -f "$mcp_avail/$s.json" ] && mcp_frags+=("$mcp_avail/$s.json")
done

# Selected skills as "name<TAB>dir"; an unknown group is reported and skipped.
selected=""
for g in $declared; do
  if ! jq -e --arg g "$g" 'has($g)' "$groups_file" >/dev/null; then
    echo "agent-skill-groups: unknown group '$g' in AGENTS.md" >&2
    continue
  fi
  selected+="$(jq -r --arg g "$g" '.[$g] | to_entries[] | "\(.key)\t\(.value)"' "$groups_file")"$'\n'
done
selected="$(printf '%s' "$selected" | sort -u | sed '/^$/d')"

is_store_link() {
  [ -L "$1" ] || return 1
  case "$(readlink "$1")" in
  /nix/store/*) return 0 ;;
  esac
  return 1
}

if [ "$cmd" = status ]; then
  echo "repo: $root"
  echo "groups: ${declared:-<none>}"
  for t in "${trees[@]}"; do
    [ -d "$t" ] || continue
    for l in "$t"/*; do
      is_store_link "$l" && echo "$l -> $(readlink "$l")"
    done
  done
  exit 0
fi

# Skills an enabled Claude plugin already lists. Linking those into
# .claude/skills lists them a SECOND time in the same session for no gain —
# Claude reads its enabled plugins as well as this tree. Measured in
# tofu-proxmox: 23 of 24 links were such duplicates and cost 2,988 tokens of
# every session in that repository.
#
# The other five harnesses have no plugin system to fall back on, so this
# applies to .claude/skills ONLY. Dropping a name from .agents/skills would
# make it unreachable for Codex, Cursor, OpenCode, qwen and Antigravity.
#
# Derived from live state rather than baked in, so it cannot drift out of step
# with which plugins are actually enabled. Any failure here leaves the list
# empty, which links everything — the pre-existing behaviour.
claude_provided=""
if [ -r "$HOME/.claude/settings.json" ] && command -v python3 >/dev/null 2>&1; then
  claude_provided="$(python3 - <<'EOPY' 2>/dev/null || true
import json, os, glob
home = os.path.expanduser("~")
try:
    enabled = {k.split("@")[-1] for k, v in json.load(
        open(f"{home}/.claude/settings.json")).get("enabledPlugins", {}).items() if v}
except Exception:
    raise SystemExit(0)
names = set()
for market in glob.glob(f"{home}/.claude/plugins/marketplaces/*"):
    if os.path.basename(market) not in enabled:
        continue
    for skill in glob.glob(f"{market}/*/skills/*"):
        if os.path.isfile(os.path.join(skill, "SKILL.md")):
            names.add(os.path.basename(skill))
print("\n".join(sorted(names)))
EOPY
  )"
fi

tracked="$(git ls-files -- "${trees[@]}" 2>/dev/null || true)"
for t in "${trees[@]}"; do
  wanted=""
  while IFS=$'\t' read -r name dir; do
    [ -n "$name" ] || continue
    if [ "$t" = .claude/skills ] && [ -n "$claude_provided" ] &&
      printf '%s\n' "$claude_provided" | grep -qxF "$name"; then
      continue
    fi
    wanted+="$name"$'\n'
    if [ -e "$t/$name" ] && ! is_store_link "$t/$name"; then
      echo "agent-skill-groups: $t/$name is not a managed link, left alone" >&2
      continue
    fi
    [ "$(readlink "$t/$name" 2>/dev/null)" = "$dir" ] && continue
    mkdir -p "$t"
    ln -sfn "$dir" "$t/$name"
  done <<<"$selected"
  if [ -d "$t" ]; then
    for l in "$t"/*; do
      [ -e "$l" ] || [ -L "$l" ] || continue
      is_store_link "$l" || continue
      printf '%s\n' "$wanted" | grep -qx "$(basename "$l")" || rm -f "$l"
    done
    rmdir "$t" 2>/dev/null || true
  fi
done

if grep -q '^mcp-servers:' AGENTS.md && ! git ls-files --error-unmatch -- .mcp.json >/dev/null 2>&1; then
  if [ "${#mcp_frags[@]}" -gt 0 ]; then
    jq -s 'reduce .[] as $f ({}; . * $f)' "${mcp_frags[@]}" >.mcp.json
  else
    rm -f .mcp.json
  fi
fi

# Keep the managed trees and file out of `git status` without editing tracked files.
exclude="$(git rev-parse --git-path info/exclude 2>/dev/null || true)"
if [ -n "$exclude" ] && [ -z "$tracked" ] && { [ -n "$selected" ] || [ -f .mcp.json ]; }; then
  mkdir -p "$(dirname "$exclude")"
  touch "$exclude"
  for t in "${trees[@]/%//}" /.mcp.json; do
    grep -qx "$t" "$exclude" || echo "$t" >>"$exclude"
  done
fi
