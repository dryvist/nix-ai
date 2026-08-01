#!/usr/bin/env bash
# Exercises pd_auto_reboot_if_warranted (modules/mlx/scripts/cluster-link-guards.sh)
# — the unattended reboot that clears a PD-exhaustion halt instead of waiting
# for a human to notice the alert and reboot by hand.
#
# WHY THIS EXISTS. Every earlier PD guard halts and pages, then stops: on
# 2026-08-01 a host reached "rank failed 5 consecutive starts; HALTING
# kickstarts" and sat there for hours with the Thunderbolt cable plugged in the
# whole time, because nothing issued the reboot the guard's own alert text says
# is required. That is the manual interlock the operator's chaos-monkey
# doctrine bans. This function is the fix, and this file is the test that fails
# if it regresses into either extreme: rebooting when it should not (a runaway
# loop, or a FileVault host stranded with no SSH), or staying silent when it
# should act.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — pd_auto_reboot_if_warranted itself, sourced from the shipped script
#           and called exactly as the watcher calls it (halt marker, rate-limit
#           marker, link state).
#   STUB  — sudo and fdesetup, as shell functions that shadow any real binary
#           of the same name (same trick test-pd-debt.sh already uses for
#           sysctl and hostname): sudo -n /sbin/reboot must never actually run
#           in a test, and fdesetup is macOS-only. date, so the rate-limit
#           window is asserted by the clock it COMPUTES against, not by really
#           sleeping through it. alert, through a fake curl that records the
#           POST body instead of sending it (mirrors alert-payload-test.sh).
#
# Usage:
#   BOOT_SCOPE=… LEDGER=… HELPERS=… GUARDS=… bash test-pd-auto-reboot.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

halt_file="$state_dir/rank-halted"
marker_file="$state_dir/pd-auto-reboot-last"
debt_file="$state_dir/pd-debt"

# A real file with SOME content: alert() itself is under test here (every
# reboot must page, and the FileVault refusal must page INSTEAD of rebooting),
# so unlike most other tests in this suite the URL file must actually exist —
# its content is never read by anything but the faked curl below.
export CLUSTER_ALERT_URL_FILE="$state_dir/alert-url"
echo "https://hooks.example.invalid/services/T000/B000/fake" > "$CLUSTER_ALERT_URL_FILE"
export CLUSTER_ROLE=worker
export CLUSTER_PD_DEBT_FILE="$debt_file"
export CLUSTER_PD_DEBT_MAX=5
export CLUSTER_PD_DEVICE_BUDGET=11
export CLUSTER_PD_AUTO_REBOOT_WINDOW_SECS=21600 # 6h, the shipped default

# shellcheck disable=SC1090
source "${BOOT_SCOPE:?set BOOT_SCOPE to cluster-boot-scope.sh}"
# shellcheck disable=SC1090
source "${LEDGER:?set LEDGER to cluster-pd-ledger.sh}"
# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to cluster-link-helpers.sh}"
# shellcheck disable=SC1090
source "${GUARDS:?set GUARDS to cluster-link-guards.sh}"

# --- stubs -------------------------------------------------------------------
sysctl() { echo "{ sec = 1785031601, usec = 0 } stub boottime"; }
hostname() { echo test-host; }
# NOT named `now`: pd_auto_reboot_if_warranted has its own `local now`, and
# bash locals are dynamically scoped — a nested `date()` call from inside that
# function would shadow this test's clock with the callee's still-unset local
# and blow up under `set -u`. Same reason test-rank-start-guards.sh calls its
# clock `align_now` rather than `now`.
fake_now=1000
date() {
  case "$1" in
    +%s) echo "$fake_now" ;;
    *) command date "$@" ;;
  esac
}

# sudo -n /sbin/reboot -- recorded, never really run. rc is scriptable so the
# "reboot command itself failed" path can be exercised too.
reboot_log="$state_dir/reboot-log"
reboot_rc=0
sudo() {
  printf '%s\n' "$*" >> "$reboot_log"
  return "$reboot_rc"
}
reboots() { wc -l < "$reboot_log" | tr -d ' '; }

# fdesetup status -- FileVault state under test.
filevault=off
fdesetup() {
  if [ "$1" = status ]; then
    if [ "$filevault" = on ]; then echo "FileVault is On."; else echo "FileVault is Off."; fi
  fi
}

# quiesce_normal_serving talks to CLUSTER_NORMAL_PROXY / CLUSTER_QUIESCE_CMD;
# neither is set (CLUSTER_ROLE=worker, no CLUSTER_QUIESCE_CMD), so it is
# already a real no-op — no stub needed, same as other tests leave it alone.

# alert() -- through a fake curl that records one marker per call, so "an
# alert fired" is observable without a network. Not the raw args: jq's default
# pretty-printed JSON and alert()'s own `-w $'\n%{http_code}'` both embed real
# newlines INSIDE a single curl invocation's argv, which would inflate a
# line-count taken over "$*".
curl_log="$state_dir/curl-log"
curl() {
  echo call >> "$curl_log"
  echo '200'
}
alerts() { wc -l < "$curl_log" | tr -d ' '; }

fail=0
check() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    echo "  ok   $label -> $got"
  else
    echo "  FAIL $label -> got '$got', want '$want'"
    fail=1
  fi
}
write_halt() {
  printf '2026-08-01T00:00:00Z\tcause=%s\tboot=1785031601\t%s\n' "$1" "${2:-detail}" > "$halt_file"
}
reset_state() {
  rm -f "$halt_file" "$marker_file" "$debt_file"
  : > "$reboot_log"
  : > "$curl_log"
  fake_now=1000
  filevault=off
  reboot_rc=0
}
reset_state

echo "1. link down -- never reboots, whatever the halt says:"
reset_state
write_halt pd-debt-exhausted
pd_auto_reboot_if_warranted "$halt_file" "$marker_file" down
check "no reboot attempted" 0 "$(reboots)"
check "no alert fired" 0 "$(alerts)"
check "no rate-limit marker written" absent "$([ -f "$marker_file" ] && echo written || echo absent)"

echo "2. a non-PD halt cause -- never reboots (a reboot would not fix it):"
reset_state
write_halt warm-wedged
pd_auto_reboot_if_warranted "$halt_file" "$marker_file" up
check "no reboot for a wedged-warm halt" 0 "$(reboots)"
reset_state
write_halt manual-clear-rejected
pd_auto_reboot_if_warranted "$halt_file" "$marker_file" up
check "no reboot for a rejected manual clear" 0 "$(reboots)"
reset_state
write_halt no-token-progress
pd_auto_reboot_if_warranted "$halt_file" "$marker_file" up
check "no reboot for a peer-liveness halt" 0 "$(reboots)"

echo "3. a PD-exhaustion cause, link up, FileVault off -- reboots and pages:"
reset_state
write_halt pd-debt-exhausted
pd_auto_reboot_if_warranted "$halt_file" "$marker_file" up
check "reboot was issued" 1 "$(reboots)"
check "through sudo -n /sbin/reboot" "-n /sbin/reboot" "$(cat "$reboot_log")"
check "the page went out" 1 "$(alerts)"
check "the rate-limit marker now holds this tick's clock" "$fake_now" "$(cat "$marker_file")"

echo "   ...and the same is true of the OTHER PD-exhaustion cause:"
reset_state
write_halt rank-start-failures
pd_auto_reboot_if_warranted "$halt_file" "$marker_file" up
check "rank-start-failures reboots too" 1 "$(reboots)"

echo "4. the rate limit blocks a second reboot inside the window:"
reset_state
write_halt pd-debt-exhausted
pd_auto_reboot_if_warranted "$halt_file" "$marker_file" up
check "first reboot fires" 1 "$(reboots)"
fake_now=$((fake_now + 60)) # 1 minute later, well inside the 6h window
pd_auto_reboot_if_warranted "$halt_file" "$marker_file" up
check "second attempt inside the window is refused" 1 "$(reboots)"
check "no second page either" 1 "$(alerts)"
echo "   ...and fires again once the window has actually elapsed:"
fake_now=$((fake_now + 21600))
pd_auto_reboot_if_warranted "$halt_file" "$marker_file" up
check "past the window, a fresh reboot is allowed" 2 "$(reboots)"

echo "5. window=0 disables auto-reboot outright (the escape hatch):"
reset_state
write_halt pd-debt-exhausted
CLUSTER_PD_AUTO_REBOOT_WINDOW_SECS=0 pd_auto_reboot_if_warranted "$halt_file" "$marker_file" up
check "0 means never" 0 "$(reboots)"
check "and no marker is written either" absent "$([ -f "$marker_file" ] && echo written || echo absent)"

echo "6. FileVault on -- refuses even at the cap, pages instead of stranding the host:"
reset_state
write_halt pd-debt-exhausted
filevault=on
pd_auto_reboot_if_warranted "$halt_file" "$marker_file" up
check "no reboot attempted" 0 "$(reboots)"
check "a page still went out (the incident is not silent)" 1 "$(alerts)"
check "no rate-limit marker consumed either (nothing happened to limit)" absent \
  "$([ -f "$marker_file" ] && echo written || echo absent)"

echo "7. a failed reboot command still leaves the marker set (do not hot-loop retrying):"
reset_state
write_halt pd-debt-exhausted
reboot_rc=1
pd_auto_reboot_if_warranted "$halt_file" "$marker_file" up
check "the attempt was made" 1 "$(reboots)"
check "the marker is still recorded" "$fake_now" "$(cat "$marker_file" 2> /dev/null || echo missing)"

exit "$fail"
