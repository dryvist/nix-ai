#!/usr/bin/env bash
# Remove token-meter's LaunchAgents when the module is disabled.
#
# Nix never wrote these two agents — upstream's own ./scripts/install did,
# into ~/Library/LaunchAgents with RunAtLoad=true. Nothing in a rebuild
# removes a file nix did not create, so without this `enable = false` leaves
# the dashboard running forever and the option is a lie. Verified on the
# laptop: after disabling the module, both plists were still on disk and
# would have restarted at the next login.
#
# Idempotent and silent on hosts that never had it: the loop skips any label
# whose plist is absent, which is every host that never enabled the module.
set -uo pipefail

for label in com.token-meter.server com.token-meter.menubar; do
  plist="$HOME/Library/LaunchAgents/$label.plist"
  [ -e "$plist" ] || continue
  # A bootout failure is not fatal — the agent may already be unloaded, and
  # removing the plist is what makes the change survive a reboot either way.
  /bin/launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  rm -f "$plist"
  echo "token-meter: removed $label"
done
