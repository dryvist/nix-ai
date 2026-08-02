#!/usr/bin/env bash
# THE CHECK THAT FAILS IF THE 86-HOUR OUTAGE CAN RECUR.
#
# On 2026-08-01 the Thunderbolt link was down for 86 hours with the cable
# seated. A port had carrier the whole time; this host simply held no link
# address, because it had drifted off the deployed system generation and the
# activation that aliases the address never ran. The watcher probed the peer,
# failed, and logged the same two-item GUESS 10,440 times — "cable out, OR denied
# macOS Local Network permission" — while never once looking at its own link
# prep, for which it already carried the repair.
#
# Properties, all against the REAL shipped functions:
#   1. carrier + no address  -> the repair runs, unattended;
#   2. no carrier            -> no repair is attempted (nothing to fix, and
#                               thrashing bridge0 every 30s for days is not
#                               persistence);
#   3. a repair that cannot work stops at the cap, and a healthy tick resets it;
#   4. the report is MEASURED STATE — per-port carrier, where the address is,
#      generation parity, whether the peer answered — with no cause list;
#   5. drift is a field of that report, cached to a TTL, and pages once per
#      distinct drift rather than once per tick.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — link_prep_self_heal, link_facts, tb_carrier_facts, self_ip_fact,
#           generation_parity_cached, generation_drift_report and
#           generation_parity_fact are sourced from the shipped layers and called
#           as the watcher calls them.
#   STUB  — tb_devices / first_carrier_tb_device / link_prep_ok /
#           iface_holding_self_ip / repair_link_prep, each a thin wrapper over a
#           macOS-only binary (networksetup, ifconfig) absent on a Linux runner;
#           ifconfig itself through the CLUSTER_IFCONFIG_BIN seam; the two
#           revision readers; and alert, so a page is observable, not posted.
#
# Stub state is named stub_* on purpose: bash scoping is dynamic, so a global
# sharing a name with a `local` inside the function under test would be shadowed
# by it and the stub would silently read the wrong value.
#
# Usage:
#   FACTS=/path/to/cluster-link-facts.sh \
#   PARITY=/path/to/cluster-generation-parity.sh bash test-link-self-heal.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

counter_file="$state_dir/link-prep-repairs"
parity_cache="$state_dir/generation-parity"
alert_marker="$state_dir/generation-alerted"
pages="$state_dir/pages"
: > "$pages"

# RFC 5737 documentation addresses: this test never touches a real link.
export CLUSTER_STATIC_SELF_IP=192.0.2.2
export CLUSTER_STATIC_PEER_IP=192.0.2.1
export CLUSTER_GENERATION_REPO=example/deploy

# shellcheck disable=SC1090
source "${PARITY:?set PARITY to the path of cluster-generation-parity.sh}"
# shellcheck disable=SC1090
source "${FACTS:?set FACTS to the path of cluster-link-facts.sh}"

# --- stubs for the macOS-only wrappers, plus observation counters -----------
stub_carrier=""       # device name with carrier, empty = cable out
stub_prep=0           # 1 = this host holds its link address on a usable port
stub_holder=""        # interface currently holding the address
stub_repairs=0        # repair_link_prep call count
stub_repair_ok=0      # whether the stubbed repair actually fixes prep
stub_ports=""         # newline-separated Thunderbolt devices

tb_devices() { printf '%s\n' "$stub_ports"; }
first_carrier_tb_device() {
  [ -n "$stub_carrier" ] || return 1
  printf '%s' "$stub_carrier"
}
link_prep_ok() { [ "$stub_prep" = 1 ]; }
iface_holding_self_ip() { printf '%s' "$stub_holder"; }
repair_link_prep() {
  stub_repairs=$((stub_repairs + 1))
  if [ "$stub_repair_ok" = 1 ]; then
    stub_prep=1
    stub_holder="$stub_carrier"
    return 0
  fi
  return 1
}
alert() { printf '%s\n' "$1" >> "$pages"; }

# tb_carrier_facts shells out to ifconfig by absolute path (/sbin is not on a
# writeShellApplication PATH), so it is driven through the CLUSTER_IFCONFIG_BIN
# seam — the same seam CLUSTER_NETSTAT_BIN and CLUSTER_PING_BIN already use. A
# shell function cannot substitute for it: bash skips function lookup entirely
# for a command name containing a slash.
#
# The shebang is $BASH — the running interpreter's own absolute path — never
# `#!/usr/bin/env bash`: a Linux nix build sandbox exposes /bin/sh but no
# /usr/bin/env, so an env shebang fails to exec, every port reads as inactive,
# and the assertions that expect the code to ACT read as "nothing happened".
# That is why this test would pass on a workstation and fail only once wired up
# as a check (same fix as tests/test-peer-liveness.sh).
{
  printf '%s\n' "#!$BASH"
  cat << 'FAKE'
if [ "$1" = "${FAKE_CARRIER_DEV:-}" ]; then
  printf '\tstatus: active\n'
else
  printf '\tstatus: inactive\n'
fi
FAKE
} > "$state_dir/ifconfig"
chmod +x "$state_dir/ifconfig"
export CLUSTER_IFCONFIG_BIN="$state_dir/ifconfig"

# Parity is stubbed at its two leaf readers, so the state machine above them is
# the real one. git / darwin-version are absent on a runner and irrelevant here.
stub_local_rev="aaaaaaaaaaaa"
stub_remote_rev="aaaaaaaaaaaa"
# Counted through a FILE, not a variable: generation_parity_fact runs inside a
# command substitution, so an increment in the callee's subshell never reaches
# this scope. That is the same class of mistake as counting a pipeline's work in
# the shell that started it.
remote_reads_file="$state_dir/remote-reads"
: > "$remote_reads_file"
generation_local_rev() { printf '%s' "$stub_local_rev"; }
generation_remote_rev() {
  printf 'read\n' >> "$remote_reads_file"
  printf '%s' "$stub_remote_rev"
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
      echo "  FAIL $label -> '$needle' missing from: $hay"
      fail=1
      ;;
  esac
}
lacks() {
  local label="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*)
      echo "  FAIL $label -> '$needle' present in: $hay"
      fail=1
      ;;
    *) echo "  ok   $label" ;;
  esac
}
reset_state() {
  rm -f "$counter_file" "$parity_cache" "$alert_marker"
  : > "$pages"
  : > "$remote_reads_file"
  stub_repairs=0
  stub_repair_ok=0
}
counter_now() { cat "$counter_file" 2> /dev/null || echo absent; }
pages_sent() { grep -c . "$pages" || true; }
remote_reads() { grep -c . "$remote_reads_file" || true; }
set_carrier() {
  stub_carrier="$1"
  export FAKE_CARRIER_DEV="$1"
}

echo "stub contracts (everything below reaches these indirectly):"
set_carrier en2
stub_ports=$'en1\nen2'
check "first_carrier_tb_device names the cabled port" en2 "$(first_carrier_tb_device)"
set_carrier ""
check "no carrier reports failure" 1 "$(first_carrier_tb_device > /dev/null && echo 0 || echo 1)"
set_carrier en2
stub_prep=1
stub_holder=en2
check "link_prep_ok true once prep is healthy" 0 "$(link_prep_ok && echo 0 || echo 1)"
check "iface_holding_self_ip names the holder" en2 "$(iface_holding_self_ip)"
stub_prep=0
stub_holder=""
check "link_prep_ok false with no address" 1 "$(link_prep_ok && echo 0 || echo 1)"

echo
echo "THE INCIDENT: carrier present, address absent -> repair, unattended:"
# This is the state the machine sat in for 86 hours while the watcher logged a
# guess about the cable. Nothing here waits for a human.
reset_state
set_carrier en2
stub_prep=0
stub_holder=""
stub_repair_ok=1
link_prep_self_heal "$counter_file" && healed=0 || healed=1
check "self-heal repaired the link" 0 "$healed"
check "the repair actually ran" 1 "$stub_repairs"
check "prep is healthy afterwards" 0 "$(link_prep_ok && echo 0 || echo 1)"
check "counter cleared by a successful repair" absent "$(counter_now)"

echo
echo "cable genuinely out -> NO repair attempted:"
# No carrier means there is nothing to repair. Freeing ports from bridge0 and
# re-aliasing every 30s for days would be churn, not persistence.
reset_state
set_carrier ""
stub_prep=0
stub_holder=""
link_prep_self_heal "$counter_file" && healed=0 || healed=1
check "self-heal reports prep still broken" 1 "$healed"
check "no repair attempted without carrier" 0 "$stub_repairs"
check "no attempt counted" absent "$(counter_now)"

echo
echo "a repair that cannot work is BOUNDED (no thrash):"
reset_state
set_carrier en2
stub_prep=0
stub_holder=""
stub_repair_ok=0
export CLUSTER_LINK_PREP_MAX_REPAIRS=3
for _ in 1 2 3 4 5 6; do link_prep_self_heal "$counter_file" || true; done
check "stopped at the cap" 3 "$stub_repairs"
check "counter holds the attempts" 3 "$(counter_now)"

echo "...and a healthy tick clears the count, so a later fault gets a fresh budget:"
stub_prep=1
stub_holder=en2
link_prep_self_heal "$counter_file" && healed=0 || healed=1
check "healthy prep returns success" 0 "$healed"
check "counter cleared" absent "$(counter_now)"
stub_prep=0
stub_holder=""
link_prep_self_heal "$counter_file" || true
check "repairs resume after the reset" 4 "$stub_repairs"

echo
echo "the report is OBSERVED STATE, not a cause list:"
# The defect this pins: the old line offered two causes and omitted the real one,
# so a reader picked one of the two and diagnosed the wrong machine.
reset_state
set_carrier en2
stub_ports=$'en1\nen2'
stub_prep=0
stub_holder=""
facts="$(link_facts no "$parity_cache")"
contains "names every Thunderbolt port with its carrier" "tb-ports[ en1=inactive en2=active ]" "$facts"
contains "says where the self address is (nowhere)" "self 192.0.2.2 NOT-ALIASED" "$facts"
contains "attributes prep to the port with carrier" "MISSING-WITH-CARRIER(link prep never ran on en2" "$facts"
contains "states the cable is not the fault" "not a cable fault" "$facts"
contains "reports whether the peer answered" "peer 192.0.2.1 answered=no" "$facts"
contains "reports generation parity" "generation state=ok" "$facts"
lacks "offers no guess about the cable" "cable out, OR" "$facts"
lacks "offers no guess about Local Network permission" "Local Network permission" "$facts"

echo
echo "...and it distinguishes a real unplug from a missing address:"
reset_state
set_carrier ""
stub_prep=0
stub_holder=""
facts="$(link_facts no "$parity_cache")"
contains "no carrier is reported as no carrier" "prep NO-CARRIER" "$facts"
lacks "and is NOT reported as a missing prep" "MISSING-WITH-CARRIER" "$facts"

echo
echo "...and a healthy link says so, with the holding port:"
reset_state
set_carrier en2
stub_prep=1
stub_holder=en2
facts="$(link_facts yes "$parity_cache")"
contains "prep OK" "prep OK" "$facts"
contains "names the interface holding the address" "self 192.0.2.2 on en2" "$facts"
contains "peer answered" "answered=yes" "$facts"

echo
echo "generation parity is a FIELD of the facts, and drift pages once:"
# Drift is what disarmed link prep. It used to be checked only by cluster-join,
# which a human runs — so on the timer path it was never checked at all.
reset_state
stub_remote_rev="bbbbbbbbbbbb"
facts="$(link_facts no "$parity_cache")"
contains "drift is reported with both revisions" \
  "generation state=drift local=aaaaaaaaaaaa deploy=bbbbbbbbbbbb" "$facts"

generation_drift_report "$(generation_parity_cached "$parity_cache")" "$alert_marker"
check "drift pages once" 1 "$(pages_sent)"
generation_drift_report "$(generation_parity_cached "$parity_cache")" "$alert_marker"
generation_drift_report "$(generation_parity_cached "$parity_cache")" "$alert_marker"
check "and not again for the same drift" 1 "$(pages_sent)"

echo "...a NEW drift revision is a new page:"
rm -f "$parity_cache"
stub_remote_rev="cccccccccccc"
generation_drift_report "$(generation_parity_cached "$parity_cache")" "$alert_marker"
check "distinct drift pages again" 2 "$(pages_sent)"

echo "...an unstamped (dirty) build pages too — it can never match a deploy rev:"
rm -f "$parity_cache" "$alert_marker"
stub_local_rev=""
generation_drift_report "$(generation_parity_cached "$parity_cache")" "$alert_marker"
check "unstamped pages" 3 "$(pages_sent)"
stub_local_rev="aaaaaaaaaaaa"

echo "...and parity coming back clears the latch instead of paging:"
rm -f "$parity_cache"
stub_remote_rev="aaaaaaaaaaaa"
generation_drift_report "$(generation_parity_cached "$parity_cache")" "$alert_marker"
check "healthy parity sends no page" 3 "$(pages_sent)"
check "latch cleared, so a later drift pages again" absent \
  "$([ -f "$alert_marker" ] && echo present || echo absent)"

echo
echo "an unreachable deploy branch is UNVERIFIED, never drift:"
# Offline is a legitimate state. Treating it as drift would page every laptop
# that leaves the house; treating it as OK would hide the real thing.
reset_state
stub_remote_rev=""
generation_drift_report "$(generation_parity_cached "$parity_cache")" "$alert_marker"
check "no page when the remote is unreachable" 0 "$(pages_sent)"
contains "reported as unverified" "state=unverified" "$(cat "$parity_cache")"
stub_remote_rev="aaaaaaaaaaaa"

echo
echo "the parity cache honours its TTL (one ls-remote per interval, not per tick):"
# A watcher tick every 30s must not mean a network round trip every 30s, and the
# facts line must not flap with the network rather than with the system.
reset_state
export CLUSTER_GENERATION_CHECK_SECS=3600
generation_parity_cached "$parity_cache" > /dev/null
generation_parity_cached "$parity_cache" > /dev/null
generation_parity_cached "$parity_cache" > /dev/null
check "three ticks, one remote read" 1 "$(remote_reads)"
# An expired stamp must refresh. Rewritten rather than waited out: the cache
# carries its own epoch precisely so age is testable without sleeping.
printf '1 state=ok local=stale deploy=stale\n' > "$parity_cache"
generation_parity_cached "$parity_cache" > /dev/null
check "an expired entry is refreshed" 2 "$(remote_reads)"

echo
echo "call sites in cluster-link-watcher.sh (a function nobody calls fixes nothing):"
# The whole incident is a function that existed and was never reached from the
# path that needed it, so behaviour assertions alone would prove nothing here.
watcher="${WATCHER:?set WATCHER to the path of cluster-link-watcher.sh}"
# Code lines only: the comments legitimately quote the message being removed.
code() { grep -v '^[[:space:]]*#' "$watcher"; }
pin() {
  local label="$1" pattern="$2"
  if grep -Eq "$pattern" <<< "$(code)"; then
    echo "  ok   $label"
  else
    echo "  FAIL $label -> no code line matching /$pattern/"
    fail=1
  fi
}
anti_pin() {
  local label="$1" pattern="$2"
  if grep -Eq "$pattern" <<< "$(code)"; then
    echo "  FAIL $label -> code line matching /$pattern/ is back"
    fail=1
  else
    echo "  ok   $label"
  fi
}
pin "the watcher self-heals its own link prep while the link reads down" \
  '(^|[^_[:alnum:]])link_prep_self_heal'
pin "the watcher reports measured facts" '(^|[^_[:alnum:]])link_facts'
pin "the watcher checks generation parity on its timer" \
  '(^|[^_[:alnum:]])generation_drift_report'
pin "an unchanged state is throttled by the derived cadence" 'CLUSTER_DOWN_REPORT_EVERY'
pin "a CHANGED state is reported immediately, cadence or not" 'facts" != "\$last_facts'
anti_pin "the two-cause guess is gone" 'cable out, OR'
anti_pin "and so is the Local Network permission guess" 'Local Network permission'
# Ordering: repairing after reporting would describe a state the watcher had
# already decided to leave alone.
heal_line="$(grep -n 'link_prep_self_heal' "$watcher" | head -n1 | cut -d: -f1)"
facts_line="$(grep -n 'facts="\$(link_facts' "$watcher" | head -n1 | cut -d: -f1)"
if [ -n "$heal_line" ] && [ -n "$facts_line" ] && [ "$heal_line" -lt "$facts_line" ]; then
  echo "  ok   the repair runs before the report, so the report describes what it left behind"
else
  echo "  FAIL self-heal (line ${heal_line:-none}) must precede the facts line (line ${facts_line:-none})"
  fail=1
fi

exit "$fail"
