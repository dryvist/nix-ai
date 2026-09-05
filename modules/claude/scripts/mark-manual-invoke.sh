#!/usr/bin/env bash
# Mark marketplace skills manual-invoke.
#
# Every SKILL.md gains `disable-model-invocation: true` unless its directory
# name is in $KEEP_LISTED. A marked skill leaves the session's skill listing
# but stays callable by /name, which is what makes this a saving rather than a
# capability loss.
#
# Measured 2026-09-02 in nix-ai with a probe skill: a listed skill carrying a
# ~2000-character description costs 518 tokens of every session start; the same
# skill marked manual-invoke costs 10.
#
# $1 = source marketplace tree, $2 = output path.
set -euo pipefail

src="$1"
out="$2"

cp -RL "$src" "$out"
chmod -R u+w "$out"

marked=0
kept=0
while IFS= read -r -d '' f; do
  name="$(basename "$(dirname "$f")")"
  case " ${KEEP_LISTED:-} " in
    *" $name "*)
      kept=$((kept + 1))
      continue
      ;;
  esac
  # Only touch files that actually open with YAML frontmatter, and never
  # double-add the key.
  #
  # Both checks are scoped to the frontmatter block, never the whole file. A
  # skill whose *body* documents the key — a skill about authoring skills, say
  # — would otherwise match a whole-file grep and be silently left listed.
  # Two shipped skills hit exactly that and stayed in every session's listing.
  [ "$(head -n 1 "$f")" = "---" ] || continue
  awk 'NR>1 && /^---$/ { exit } NR>1 && /^disable-model-invocation:/ { found=1 }
       END { exit !found }' "$f" && continue
  awk 'NR==1 { print; print "disable-model-invocation: true"; next } { print }' \
    "$f" >"$f.mi" && mv "$f.mi" "$f"
  marked=$((marked + 1))
done < <(find "$out" -name SKILL.md -type f -print0)

echo "manual-invoke: marked=$marked kept-listed=$kept" >&2
