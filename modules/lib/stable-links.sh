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
set -euo pipefail

manifest="$1"
home="$2"

created=0
unchanged=0

# Roots we manage, collected so stale entries can be pruned without touching
# anything a user or another tool put there.
roots_file="$(mktemp)"
trap 'rm -f "$roots_file" "$roots_file.managed"' EXIT
: >"$roots_file.managed"

while IFS=$'\t' read -r rel target; do
  [ -n "${rel:-}" ] || continue
  [ -n "${target:-}" ] || continue
  dest="$home/$rel"
  dirname "$dest" >>"$roots_file"
  echo "$dest" >>"$roots_file.managed"

  if [ "$(readlink "$dest" 2>/dev/null)" = "$target" ]; then
    unchanged=$((unchanged + 1))
    continue
  fi

  mkdir -p "$(dirname "$dest")"
  # A previous generation may have left a real directory here (home-manager
  # copies, or a CLI that re-cloned the tree in place). Replace it.
  rm -rf "$dest"
  ln -s "$target" "$dest"
  created=$((created + 1))
done <"$manifest"

# Prune links we used to manage and no longer do. Only ever remove a symlink
# that points into the nix store: never a real file, and never something
# pointing outside it.
pruned=0
sort -u "$roots_file" | while IFS= read -r root; do
  [ -d "$root" ] || continue
  for link in "$root"/*; do
    [ -L "$link" ] || continue
    grep -qxF "$link" "$roots_file.managed" && continue
    case "$(readlink "$link")" in
      /nix/store/*)
        rm -f "$link"
        pruned=$((pruned + 1))
        ;;
    esac
  done
done

echo "stable-links: linked=$created unchanged=$unchanged" >&2
