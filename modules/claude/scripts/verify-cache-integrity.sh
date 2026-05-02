#!/usr/bin/env bash
# Verify Claude Code plugin cache integrity after Nix rebuilds
# Removes stale cache entries when marketplace store paths change
#
# When Nix updates marketplace symlinks to new /nix/store paths,
# Claude Code's cached plugin data becomes stale and must be purged.
# See: https://github.com/anthropics/claude-code/issues/17361

set -euo pipefail

# Centralized logging function (stderr for diagnostics)
log_info() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" >&2
}

HOME_DIR="${1:?Usage: verify-cache-integrity.sh <home-dir>}"
MARKETPLACES_DIR="$HOME_DIR/.claude/plugins/marketplaces"
CACHE_DIR="$HOME_DIR/.claude/plugins/cache"
HASH_FILE="$CACHE_DIR/.nix-store-hashes"

# Resolve the SHA-256 hasher once at startup into _SHA_CMD.
# Prefer shasum from PATH (present on macOS and installable cross-platform),
# fall back to the macOS system copy, then sha256sum (Linux coreutils).
# sha256sum does not accept -a 256, so wrap the call to normalise the interface.
# NOTE: _SHA_CMD must persist — sha256_string references it at call time, not
# definition time. Using a temporary that gets unset causes "unbound variable"
# under set -u, silently breaking cache integrity on every darwin-rebuild switch.
if _SHA_CMD=$(command -v shasum 2>/dev/null) || { [ -x /usr/bin/shasum ] && _SHA_CMD=/usr/bin/shasum; }; then
  sha256_string() { "$_SHA_CMD" -a 256; }
elif _SHA_CMD=$(command -v sha256sum 2>/dev/null); then
  sha256_string() { "$_SHA_CMD"; }
else
  echo "error: no shasum or sha256sum found" >&2
  exit 1
fi

# Only run if both dirs exist
[[ -d "$MARKETPLACES_DIR" ]] || exit 0
[[ -d "$CACHE_DIR" ]] || exit 0

# Load existing hashes
declare -A old_hashes
if [[ -f "$HASH_FILE" ]]; then
  while IFS='=' read -r key value; do
    [[ -n "$key" ]] && old_hashes["$key"]="$value"
  done < "$HASH_FILE"
fi

# Build new hashes and detect staleness
# Marketplaces are directory symlinks to /nix/store/ (plugins.nix without recursive)
declare -A new_hashes
declare -a stale_names
stale_detected=false
while IFS= read -r -d '' entry; do
  name=$(basename "$entry")

  # Directory symlink: target is the nix store path itself
  target=$(readlink "$entry")
  [[ "$target" == /nix/store/* ]] || continue

  # Hash the store path string (not file contents - that's what matters for staleness)
  hash=$(printf '%s' "$target" | sha256_string | cut -d' ' -f1)
  new_hashes["$name"]="$hash"

  if [[ "${old_hashes[$name]:-}" != "$hash" ]]; then
    stale_detected=true
    stale_names+=("$name")
  fi
done < <(find "$MARKETPLACES_DIR" -mindepth 1 -maxdepth 1 -type l -print0)

# Write a refresh marker so the sessionStart hook can update marketplace indexes.
# Writing a marker file is safe — it does not invoke claude or mutate cache directories.
if [[ "$stale_detected" == true ]]; then
  REFRESH_MARKER="$CACHE_DIR/.nix-refresh-needed"
  tmp_marker="$(mktemp "${REFRESH_MARKER}.XXXXXX")"
  echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmp_marker"
  for name in "${stale_names[@]}"; do
    echo "marketplace=$name" >> "$tmp_marker"
  done
  mv "$tmp_marker" "$REFRESH_MARKER"
  log_info "Wrote marketplace refresh marker: $REFRESH_MARKER"
fi

# Session-aware guard: if caches are stale but Claude Code is running, defer the
# purge to avoid breaking active sessions. Hook scripts inside cache directories are
# resolved at session start — deleting them mid-session causes an unbreakable error
# loop (every hook fails, including Stop). By also skipping the hash file update,
# the next rebuild will re-detect staleness and purge when no sessions are active.
PGREP_BIN=$(command -v pgrep || true)
if [[ -n "$PGREP_BIN" && "$stale_detected" == true ]] && "$PGREP_BIN" -qx "claude"; then
  log_info "Stale caches detected but Claude Code session is active — deferring purge"
  exit 0
fi

# Purge stale caches (safe — no active sessions)
for name in "${!new_hashes[@]}"; do
  if [[ "${old_hashes[$name]:-}" != "${new_hashes[$name]}" ]]; then
    if [[ -d "$CACHE_DIR/$name" ]]; then
      rm -rf "${CACHE_DIR:?}/$name"
      log_info "Purged stale cache: $name"
    fi
  fi
done

# Write updated hashes atomically to avoid leaving a partially written file
mkdir -p "$CACHE_DIR"
tmp_hash_file="$(mktemp "${HASH_FILE}.XXXXXX")"
for name in "${!new_hashes[@]}"; do
  echo "${name}=${new_hashes[$name]}" >> "$tmp_hash_file"
done
mv "$tmp_hash_file" "$HASH_FILE"
