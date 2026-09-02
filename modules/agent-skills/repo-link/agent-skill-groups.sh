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
# ever created or removed; a repository's own skills are never touched. Nothing
# is committed: the two directories go into .git/info/exclude.

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

# Frontmatter value of skill-groups, one name per line.
declared="$(awk '
  NR==1 && $0!="---" { exit }
  NR>1 && $0=="---" { exit }
  /^skill-groups:/ {
    v=$0; sub(/^skill-groups:[ \t]*/, "", v)
    if (v ~ /^\[/) {
      gsub(/[\[\]]/, "", v); n=split(v, a, /[ \t]*,[ \t]*/)
      for (i=1;i<=n;i++) if (a[i]!="") print a[i]
      exit
    }
    inlist=1; next
  }
  inlist && /^[ \t]*-[ \t]+/ { s=$0; sub(/^[ \t]*-[ \t]+/, "", s); print s; next }
  inlist { exit }
' AGENTS.md | tr -d "\"'")"

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

tracked="$(git ls-files -- "${trees[@]}" 2>/dev/null || true)"
for t in "${trees[@]}"; do
  wanted=""
  while IFS=$'\t' read -r name dir; do
    [ -n "$name" ] || continue
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

# Keep the managed trees out of `git status` without editing tracked files.
exclude="$(git rev-parse --git-path info/exclude 2>/dev/null || true)"
if [ -n "$exclude" ] && [ -z "$tracked" ] && [ -n "$selected" ]; then
  mkdir -p "$(dirname "$exclude")"
  touch "$exclude"
  for t in "${trees[@]}"; do
    grep -qx "$t/" "$exclude" || echo "$t/" >>"$exclude"
  done
fi
