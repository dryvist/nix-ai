#!/usr/bin/env bash
# Clone or update splunk/token-meter, then run its own installer detached.
# Called by home.activation (see modules/token-meter.nix).
set -euo pipefail

repo="$1"
src="$2"
stamp="$3"
log_dir="$4"
keep_menubar="$5"

mkdir -p "$log_dir"

if [ -d "$src/.git" ]; then
  git -C "$src" pull --quiet --ff-only || echo "token-meter: could not fast-forward $src" >&2
else
  git clone --quiet "$repo" "$src" || echo "token-meter: clone of $repo failed" >&2
fi

head=$(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo unknown)

# Upstream's installer builds a Swift binary and then polls its own health
# endpoint for up to 600s, exiting non-zero on timeout, so it runs detached
# instead of blocking (and possibly failing) the activation. The stamp is
# written only on success: upstream's own INSTALLED_REVISION is written before
# that health check, so it cannot distinguish a half-finished install.
{
  if [ "$head" != "$(cat "$stamp" 2>/dev/null || true)" ]; then
    if "$src/scripts/install"; then
      printf '%s' "$head" >"$stamp"
    else
      echo "token-meter: scripts/install failed (it needs Xcode CLT swiftc)" >&2
    fi
  fi

  # The installer always registers the menu bar agent and has no flag to skip
  # it, so removing it happens afterwards — and the plist must go too, or login
  # reloads it.
  if [ "$keep_menubar" != "1" ]; then
    launchctl bootout "gui/$(id -u)/com.token-meter.menubar" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/com.token-meter.menubar.plist"
  fi
} >>"$log_dir/install.log" 2>&1 &
