#!/usr/bin/env bash
# Guarded idempotent link reclamation for Cursor CLI agent names.
# Re-asserts Nix ownership of ~/.local/bin/agent and ~/.local/bin/cursor-agent
# on every home-manager activation, countering the self-updater's runtime rewrites.
#
# Arguments:
#   $1 - Absolute path of the Nix binary (e.g., /nix/store/.../bin/cursor-agent)
#   $2 - Target directory (e.g., /home/user/.local/bin)
#
# Per target name in {cursor-agent, agent}:
#   - Reject with exit 1 if the target exists as a REAL directory (message names it)
#   - Otherwise create the parent with mkdir -p first
#   - Then link with ln -sfn "$1" <dir>/<name>
#   - Emit an [INFO] line when replacing a file or a symlink (helps diagnosis)
# Must-NOT: touch any other ~/.local/bin entry; do NOT operate without first
# creating the parent directory; do NOT descend into a real directory.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: cursor-reclaim-links <nix-binary-path> <target-directory>" >&2
  exit 1
fi

NIX_BINARY="$1"
TARGET_DIR="$2"

# Validate NIX_BINARY exists and is a file
if [[ ! -f "$NIX_BINARY" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Nix binary not found: $NIX_BINARY" >&2
  exit 1
fi

# Ensure parent directory exists
mkdir -p "$TARGET_DIR"

# Target names to reclaim (the two names the IDE wrapper and installer contract require)
NAMES=("cursor-agent" "agent")

for name in "${NAMES[@]}"; do
  TARGET="$TARGET_DIR/$name"

  if [[ -d "$TARGET" && ! -L "$TARGET" ]]; then
    # Real directory collision - refuse and report
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Target exists as a real directory, refusing to overwrite: $TARGET" >&2
    exit 1
  fi

  if [[ -f "$TARGET" && ! -L "$TARGET" ]]; then
    # Regular file - replace with symlink
    ln -sfn "$NIX_BINARY" "$TARGET"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Replaced file with symlink: $TARGET -> $NIX_BINARY"
  elif [[ -L "$TARGET" ]]; then
    # Symlink - replace (idempotent if already pointing to same target)
    ln -sfn "$NIX_BINARY" "$TARGET"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Replaced symlink: $TARGET -> $NIX_BINARY"
  else
    # Absent - create new symlink
    ln -sfn "$NIX_BINARY" "$TARGET"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Created symlink: $TARGET -> $NIX_BINARY"
  fi
done