#!/usr/bin/env bash
# THE CHECK THAT FAILS IF A LIVE WATCHER AND A DEAD ONE LOG THE SAME THING.
#
# Every branch of the link watcher logs when it DECIDES something. A nominal
# tick — link up, rank running, nothing to converge — decides nothing and so
# wrote nothing at all, which made a watcher ticking perfectly and a watcher
# that had stopped being scheduled byte-identical in the log. That ambiguity is
# what turned the 2026-08-08 silent halt into a 14-minute one; the halted branch
# has since been made to speak every tick, and this is the same fix for the
# healthy path, where the ONLY available signal is the absence of the line.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — the heartbeat block is EXTRACTED FROM THE SHIPPED
#           cluster-link-watcher.sh between its own comment markers and
#           executed, so a drift in the shipped cadence or fields fails here.
#           rank_process_running / rank_process_absent come from the shipped
#           cluster-rank-status.sh.
#   STUB  — mem_stat_mb (its vm_stat parsing is pinned by
#           tests/test-mem-headroom.sh; here only the GiB rendering is under
#           test) and pgrep, through the CLUSTER_PGREP_BIN seam.
#   PIN   — the watcher's kickstart accounting, as source: a kickstart that did
#           not launch must not be counted, or a booted-out rank job (which is
#           exactly what cluster-detach leaves for the length of a teardown)
#           manufactures protection-domain debt out of nothing.
#
# Usage:
#   STATUS=… WATCHER=… bash test-watcher-heartbeat.sh
set -o errexit -o nounset -o pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

state_dir="$tmp/state"
mkdir -p "$state_dir" "$tmp/bin"
# Read only from inside the extracted block, which shellcheck cannot see into.
# shellcheck disable=SC2034
heartbeat_file="$state_dir/heartbeat-ticks"

export CLUSTER_RANK_PROCESS_PATTERN='/mlx_lm\.server'

# shellcheck disable=SC1090
source "${STATUS:?set STATUS to cluster-rank-status.sh}"

watcher="${WATCHER:?set WATCHER to cluster-link-watcher.sh}"

# The shipped block itself, between its own markers, minus the trailing line
# that begins the next section. Empty extraction = the markers moved, which
# must fail loudly rather than test nothing.
heartbeat_block="$(awk '/^# HEARTBEAT — A HEALTHY WATCHER/,/^# Consume the link-state edge/' "$watcher" | sed '$d')"
case "$heartbeat_block" in
  *CLUSTER_HEARTBEAT_EVERY*) ;;
  *)
    echo "FAIL could not extract the heartbeat block from $watcher" >&2
    exit 1
    ;;
esac

cat > "$tmp/bin/fake-pgrep" << PGREP
#!$BASH
exit "\$(cat '$tmp/pgrep-rc' 2>/dev/null || echo 1)"
PGREP
chmod +x "$tmp/bin/fake-pgrep"
export CLUSTER_PGREP_BIN="$tmp/bin/fake-pgrep"

# 52315 MB wired = the 2026-08-01 leak capture, rendered as 51GiB.
mem_stat_mb() {
  [ "${FAKE_VMSTAT_OK:-1}" = 1 ] || return 1
  echo "59523 52315"
}

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
contains() {
  local label="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) echo "  ok   $label" ;;
    *)
      echo "  FAIL $label -> '$needle' not in: $hay"
      fail=1
      ;;
  esac
}

# One tick of the shipped block, with the two variables the watcher holds at
# that point supplied as the watcher supplies them.
tick() {
  # shellcheck disable=SC2034  # read by the extracted block
  cur="$1"
  eval "$heartbeat_block"
}
reset() {
  rm -f "$heartbeat_file" "$tmp/pgrep-rc"
  export FAKE_VMSTAT_OK=1
}

echo "the heartbeat fires on a cadence, not on every tick:"

reset
export CLUSTER_HEARTBEAT_EVERY=3
out="$(tick up)$(tick up)"
check "ticks 1 and 2 stay quiet" "" "$out"
check "but are counted, so a gap in the numbering is readable" 2 "$(cat "$heartbeat_file")"
out="$(tick up)"
contains "tick 3 speaks" "HEARTBEAT tick 3" "$out"
out="$(tick up)$(tick up)"
check "and then goes quiet again" "" "$out"
out="$(tick up)"
contains "until the next multiple" "HEARTBEAT tick 6" "$out"

echo
echo "it carries the four facts the operator asks for first:"

reset
export CLUSTER_HEARTBEAT_EVERY=1
printf '0\n' > "$tmp/pgrep-rc"
out="$(tick up)"
contains "the link state" "link up" "$out"
contains "the rank state" "rank running" "$out"
contains "wired memory, in GiB" "wired 51GiB" "$out"
contains "and how to read a missing one" "the watcher is not running" "$out"

reset
export CLUSTER_HEARTBEAT_EVERY=1
printf '1\n' > "$tmp/pgrep-rc"
out="$(tick down)"
contains "a down link is reported, not skipped" "link down" "$out"
contains "an absent rank reads as none" "rank none" "$out"

# Three-valued, like every other rank report in this subsystem: an unanswerable
# probe is a different operator action from a rank that is genuinely not there,
# and collapsing them is the bug class cluster-rank-status.sh exists to prevent.
reset
export CLUSTER_HEARTBEAT_EVERY=1
printf '2\n' > "$tmp/pgrep-rc"
out="$(tick up)"
contains "an unanswerable probe is not reported as 'none'" "UNKNOWN" "$out"

reset
export CLUSTER_HEARTBEAT_EVERY=1
export FAKE_VMSTAT_OK=0
out="$(tick up)"
contains "an unreadable vm_stat says so rather than printing a number" "unreadable" "$out"
contains "and the heartbeat still fires" "HEARTBEAT tick 1" "$out"

echo
echo "a kickstart that launched nothing consumes no attempt:"

pin() {
  local label="$1" pattern="$2" body
  body="$(grep -v '^[[:space:]]*#' "$watcher")"
  if grep -Eq "$pattern" <<< "$body"; then
    echo "  ok   $label"
  else
    echo "  FAIL $label -> no code line matching /$pattern/ in $watcher"
    fail=1
  fi
}
pin "the counter is written only when the kickstart succeeded" \
  'if launchctl kickstart "gui/\$uid/\$CLUSTER_RANK_LABEL"; then'
pin "and a failed kickstart is logged rather than swallowed" \
  'kickstart of \$CLUSTER_RANK_LABEL FAILED'
if grep -Eq '^[[:space:]]*launchctl kickstart "gui/\$uid/\$CLUSTER_RANK_LABEL" \|\| true' "$watcher"; then
  echo '  FAIL the unconditional "|| true" kickstart is back; a failed start would be billed as a leaked domain'
  fail=1
else
  echo "  ok   no unconditional kickstart remains"
fi

exit "$fail"
