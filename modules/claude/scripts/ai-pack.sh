#!/usr/bin/env bash
# ai-pack — import a named project-scoped plugin pack into the current repo's
# committed .claude/settings.json. Claude Code deep-merges that over user
# settings on session start, so a globally-disabled (but installed) plugin is
# re-enabled only inside this repo.
#
# Packs are defined once in nix-ai (modules/claude/plugins/packs.nix) and
# rendered by Nix to ~/.config/ai-packs/<name>.json. See
# docs/architecture/plugin-scoping.md.
#
# Usage:
#   ai-pack <name>     merge pack <name> into ./.claude/settings.json
#   ai-pack --list     list available packs
#
# jq is provided via writeShellApplication runtimeInputs.
set -euo pipefail

PACK_DIR="${AI_PACKS_DIR:-$HOME/.config/ai-packs}"

available() {
  if compgen -G "$PACK_DIR"/*.json >/dev/null 2>&1; then
    for f in "$PACK_DIR"/*.json; do basename "$f" .json; done | paste -sd' ' -
  else
    echo "(none — run a darwin-rebuild first)"
  fi
}

if [[ $# -ne 1 ]]; then
  echo "Usage: ai-pack <name> | ai-pack --list" >&2
  echo "Available packs: $(available)" >&2
  exit 1
fi

if [[ "$1" == "--list" || "$1" == "-l" ]]; then
  echo "Available packs: $(available)"
  exit 0
fi

# Pack names are simple identifiers. Reject anything with path separators or
# traversal so "$1" can never escape "$PACK_DIR".
if [[ ! "$1" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ai-pack: invalid pack name '$1' (allowed: letters, digits, . _ -)" >&2
  exit 1
fi

PACK="$PACK_DIR/$1.json"
if [[ ! -f "$PACK" ]]; then
  echo "ai-pack: unknown pack '$1'. Available: $(available)" >&2
  exit 1
fi

# The merged settings are meant to be committed, so refuse to write outside a
# git work tree (avoids stranding a stray .claude/settings.json).
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ai-pack: not inside a git repository — run this from your project root" >&2
  exit 1
fi

TARGET=".claude/settings.json"
mkdir -p .claude
if [[ -f "$TARGET" ]]; then
  # Deep-merge: existing settings as base, pack overlaid (pack wins on conflict).
  tmp="$(mktemp)"
  jq -s '.[0] * .[1]' "$TARGET" "$PACK" >"$tmp"
  mv "$tmp" "$TARGET"
else
  cp "$PACK" "$TARGET"
fi

echo "ai-pack: merged '$1' into $TARGET (commit it so worktrees/teammates inherit it)"
echo "enabledPlugins now:"
jq '.enabledPlugins' "$TARGET"
