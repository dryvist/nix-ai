#!/usr/bin/env bash
# Deep-merge Nix-generated TOML settings with existing runtime state.
# Same merge strategy as merge-json-settings.sh but for TOML.
#
# Preserves runtime-only keys while updating Nix-managed settings.
# Merge strategy: existing runtime file as base, Nix config overlaid on top.
# Nix-managed keys always win, but runtime-only keys (e.g. projects) are preserved.
#
# Arguments:
#   $1 - Path to Nix-generated settings TOML (in /nix/store)
#   $2 - Path to target settings file
#
# jq and yj must be on PATH (callers ensure this via PATH export).

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: merge-toml-settings <nix-settings-path> <target-path>" >&2
  exit 1
fi

NIX_TOML="$1"
TARGET="$2"

TARGET_NAME=$(basename "$TARGET")
TARGET_DIR=$(dirname "$TARGET")
mkdir -p "$TARGET_DIR"

use_nix_config() {
  cp "$NIX_TOML" "$TARGET"
  chmod 600 "$TARGET"
}

if [[ -f "$TARGET" ]] && [[ ! -L "$TARGET" ]]; then
  # File exists and is a real file (not symlink) - merge
  # Convert both TOML files to JSON, deep-merge, convert result back to TOML
  EXISTING_JSON=$(yj -tj < "$TARGET") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Failed to parse existing ${TARGET_NAME}, using Nix config" >&2
    use_nix_config
    exit 0
  }
  NIX_JSON=$(yj -tj < "$NIX_TOML") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Failed to parse Nix ${TARGET_NAME}, keeping existing" >&2
    exit 0
  }
  # Strip Nix-authoritative sections from existing config before merge.
  # This prevents stale entries (e.g. removed MCP servers) from persisting.
  #
  # The legacy profile table and selector are stripped for a sharper reason
  # than staleness: the CLI now REFUSES to start on a config that still
  # carries either, and named profiles live in their own per-profile file
  # instead. Nix stopped emitting them, and a merge that only overlays would
  # leave the rejected keys in place forever — so the deployed config would
  # keep failing even after the fix shipped. Nothing regenerates them.
  if STRIPPED_EXISTING_JSON=$(jq 'del(.mcp_servers, .profiles, .profile)' <<< "$EXISTING_JSON"); then
    EXISTING_JSON="$STRIPPED_EXISTING_JSON"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Failed to strip Nix-authoritative sections from existing ${TARGET_NAME}, preserving existing runtime state for merge" >&2
  fi
  MERGED_JSON=$(printf '%s\n%s\n' "$EXISTING_JSON" "$NIX_JSON" | jq -s '.[0] * .[1]') || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Failed to merge ${TARGET_NAME}, using Nix config" >&2
    use_nix_config
    exit 0
  }
  printf '%s\n' "$MERGED_JSON" | yj -jt > "${TARGET}.tmp" || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Failed to convert merged ${TARGET_NAME} to TOML, using Nix config" >&2
    use_nix_config
    exit 0
  }
  mv "${TARGET}.tmp" "$TARGET"
  chmod 600 "$TARGET"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Merged ${TARGET_NAME} (preserved runtime state)"
elif [[ -L "$TARGET" ]]; then
  # It's a symlink (old Nix-managed) - remove and create real file
  rm "$TARGET"
  cp "$NIX_TOML" "$TARGET"
  chmod 600 "$TARGET"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Replaced Nix symlink with writable ${TARGET_NAME}"
else
  # No existing file - just copy
  cp "$NIX_TOML" "$TARGET"
  chmod 600 "$TARGET"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Created initial ${TARGET_NAME}"
fi
