#!/usr/bin/env bash
# Link agent trees straight to their own store paths.
#
# home-manager's `home.file` routes every managed path through one aggregate
# `home-manager-files` derivation. That derivation's hash covers the entire home
# configuration, so it changes whenever anything at all changes — a shell alias,
# an unrelated dotfile. Every symlink under it therefore acquires a new target
# on every rebuild, even when the content behind it is byte-identical.
#
# Every AI CLI caches against those paths: Claude Code's plugin registry pins
# installPaths, and Codex, Cursor, OpenCode, qwen and Antigravity all read the
# shared skill tree. When the targets move, the caches point at paths that no
# longer exist and already-running sessions break until the user reloads by
# hand.
#
# Linking each entry directly at its own store path keeps the target stable
# unless that entry's content actually changed, so an unrelated rebuild is
# invisible to a running session.
#
# $1 = manifest: TAB-separated `relative-path<TAB>store-target` lines.
# $2 = home directory.
#
# Optional: STABLE_LINKS_STORE_PREFIX overrides the store prefix that gates
# pruning, so the regression test can exercise the destructive path inside a
# tmpdir. Matches the HM_FILES_STORE_GLOB convention in the cleanup scripts.
set -euo pipefail

store_prefix="${STABLE_LINKS_STORE_PREFIX:-/nix/store/}"

manifest="$1"
home="$2"

created=0
unchanged=0
pruned=0

# Roots we manage, collected so stale entries can be pruned without touching
# anything a user or another tool put there.
roots_file="$(mktemp)"
managed_file="$roots_file.managed"
trap 'rm -f "$roots_file" "$managed_file"' EXIT
: >"$managed_file"

while IFS=$'\t' read -r rel target; do
  [ -n "${rel:-}" ] || continue
  [ -n "${target:-}" ] || continue
  dest="$home/$rel"
  dirname "$dest" >>"$roots_file"
  echo "$dest" >>"$managed_file"

  if [ "$(readlink "$dest" 2>/dev/null)" = "$target" ]; then
    unchanged=$((unchanged + 1))
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  # A previous generation may have left a real directory here (home-manager
  # copies, or a CLI that re-cloned the tree in place). Replace it.
  rm -rf "$dest"
  ln -s "$target" "$dest"
  echo "stable-links: linked $rel -> $target" >&2
  created=$((created + 1))
done <"$manifest"

# Prune links we used to manage and no longer do.
#
# Three things are deliberately never pruned:
#   * real files and directories — only symlinks are considered;
#   * symlinks pointing outside the nix store — a user's own link, or an
#     out-of-store symlink another module placed here on purpose;
#   * symlinks into home-manager's own aggregate. Those belong to
#     home-manager, which removes them itself when a generation drops them.
#     Sibling entries such as INDEX.md and GROUPS.json are still delivered
#     that way and live in the same directory as ours.
#
# The loop runs in this shell, not a pipeline subshell, so `pruned` survives
# and every removal is logged.
while IFS= read -r root; do
  [ -d "$root" ] || continue
  for link in "$root"/*; do
    [ -L "$link" ] || continue
    grep -qxF "$link" "$managed_file" && continue
    target="$(readlink "$link")"
    case "$target" in
    *-home-manager-files/*) continue ;;
    esac
    case "$target" in
    "$store_prefix"*)
      rm -f "$link"
      echo "stable-links: pruned $link -> $target" >&2
      pruned=$((pruned + 1))
      ;;
    esac
  done
done < <(sort -u "$roots_file")

echo "stable-links: linked=$created unchanged=$unchanged pruned=$pruned" >&2
