#!/usr/bin/env bash
# Mark manual-invoke in the INSTALLED plugin cache, not the marketplace source.
#
# mark-manual-invoke.sh marks a marketplace's flake input tree, which only
# reaches skills that tree actually contains. An *index* marketplace holds no
# skills at all — its marketplace.json points at ten separate plugin repos that
# Claude clones itself at install time — so nix never sees those SKILL.md files
# and they stay in every session's listing.
#
# This closes that gap at the only layer where every installed skill exists.
# It is idempotent, additive, and safe to re-run: it appends one frontmatter
# line and never removes or moves anything.
#
# Deliberately narrow:
#   - Only regular writable files. Store paths are already marked at source and
#     are read-only; skipping them keeps this from fighting the derivation.
#   - Only the frontmatter block is inspected, so a skill whose *body*
#     documents the key is still marked (the bug fixed in #2066).
#   - KEEP_LISTED names are never touched.
#
# $1 = plugin cache root.
set -euo pipefail

root="${1:?usage: mark-installed-cache.sh <plugin-cache-root>}"
[ -d "$root" ] || { echo "mark-installed-cache: no cache at $root" >&2; exit 0; }

marked=0
kept=0
already=0
unmarked=0

while IFS= read -r -d '' f; do
  # Never write through a store symlink: that content is the derivation's.
  [ -L "$f" ] && continue
  [ -w "$f" ] || continue

  name="$(basename "$(dirname "$f")")"
  case " ${KEEP_LISTED:-} " in
    *" $name "*)
      # Converge BOTH ways. Skipping a keep-listed skill is not enough: a skill
      # marked on disk and later promoted into the keep-list would stay marked
      # forever, so the promotion would apply in config and do nothing on disk,
      # with the outcome depending on which ran first. Remove the key instead.
      #
      # Precedence, stated deliberately: KEEP_LISTED wins over a marking this
      # file already carries. The keep-list is this estate's declaration of what
      # gets listed, so it overrides an upstream skill that ships marked.
      if awk 'NR>1 && /^---$/ { exit }
              NR>1 && /^disable-model-invocation:[[:space:]]*true[[:space:]]*$/ { found=1 }
              END { exit !found }' "$f"; then
        tmp="$f.mi.$$"
        if awk 'BEGIN { fm=0 }
                NR==1 { print; fm=1; next }
                fm && /^---$/ { fm=0; print; next }
                fm && /^disable-model-invocation:[[:space:]]*true[[:space:]]*$/ { next }
                { print }' "$f" >"$tmp" 2>/dev/null && mv "$tmp" "$f"; then
          unmarked=$((unmarked + 1))
        else
          rm -f "$tmp"
        fi
      fi
      kept=$((kept + 1))
      continue
      ;;
  esac

  [ "$(head -n 1 "$f")" = "---" ] || continue

  # Frontmatter block only — a body mention must not suppress marking.
  if awk 'NR>1 && /^---$/ { exit }
          NR>1 && /^disable-model-invocation:/ { found=1 }
          END { exit !found }' "$f"; then
    already=$((already + 1))
    continue
  fi

  tmp="$f.mi.$$"
  if awk 'NR==1 { print; print "disable-model-invocation: true"; next } { print }' \
       "$f" >"$tmp" 2>/dev/null && mv "$tmp" "$f"; then
    marked=$((marked + 1))
  else
    rm -f "$tmp"
  fi
done < <(find "$root" -type f -name SKILL.md -print0 2>/dev/null)

echo "mark-installed-cache: marked=$marked unmarked=$unmarked already=$already kept-listed=$kept" >&2
