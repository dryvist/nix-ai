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
  # Upstream's in-app updater fast-forwards this very checkout on its own timer,
  # so it can be left dirty or diverged by something other than us. A bare
  # --ff-only then fails on every future activation, and because the recorded
  # head still matches the stamp the installer is never re-run — pinning the
  # install to an old revision silently and permanently. The checkout is a
  # disposable mirror of upstream, so recover onto the fetched head instead.
  if ! git -C "$src" pull --quiet --ff-only; then
    echo "token-meter: fast-forward of $src failed; resetting onto origin" >&2
    git -C "$src" fetch --quiet origin && git -C "$src" reset --quiet --hard FETCH_HEAD ||
      echo "token-meter: could not reset $src onto origin" >&2
  fi
else
  git clone --quiet "$repo" "$src" || echo "token-meter: clone of $repo failed" >&2
fi

head=$(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo unknown)

# Upstream's installer builds a Swift binary and then polls its own health
# endpoint until the server finishes indexing every local session, so it runs
# detached instead of blocking activation. The stamp is written only on success:
# upstream's own INSTALLED_REVISION is written before that health check, so it
# cannot distinguish a half-finished install.
#
# That indexing pass scales with session-history size and blows through
# upstream's 600s default on a well-used machine (~2.7k sessions here). The
# timeout is not cosmetic: it fires *before* the installer registers the menu
# bar agent, so a machine that trips it loses both the menu bar and the stamp —
# and without the stamp every activation re-runs the whole doomed install. Since
# this already runs detached, a long ceiling costs nothing; keep it overridable
# for a machine whose history outgrows even this.
export TOKEN_METER_READINESS_TIMEOUT_SECONDS="${TOKEN_METER_READINESS_TIMEOUT_SECONDS:-7200}"
{
  if [ "$head" != "$(cat "$stamp" 2>/dev/null || true)" ]; then
    if "$src/scripts/install"; then
      printf '%s' "$head" >"$stamp"
    else
      echo "token-meter: scripts/install failed — see the error above and $log_dir/install.log" >&2
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
