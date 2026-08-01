#!/usr/bin/env bash
# THE CHECK THAT FAILS IF DETACHED-WHILE-PLUGGED CAN BE A STABLE STATE AGAIN.
#
# RULE 1 (operator, verbatim): "IF PLUGGED IN, then WE ARE IN CLUSTERED MODE —
# NO EXCEPTIONS." On 2026-08-01 it was violated twice by automation behaving
# "correctly": cluster-detach freed memory for a benchmark and the machines
# then sat unclustered with the cable in, and a worker sat detached-but-plugged
# after a failed join. The mechanics that made that STABLE: cluster-detach
# takes the cabled port ADMIN-down, an admin-down port reports
# `status: inactive` even with a live cable, and every repair in the watcher is
# carrier-gated — so nothing ever looked again.
#
# Properties, all against the REAL shipped functions:
#   1. a standalone lease is the ONE sanctioned exception and EXPIRES ON ITS
#      OWN — an unreadable/garbage lease reads as expired, never as indefinite;
#   2. once no lease holds, admin-down Thunderbolt ports are re-admin-upped
#      (bounded), which is what makes carrier observable and the rejoin start;
#   3. while a lease holds, the watcher leaves the machine alone entirely;
#   4. under generation drift the re-up still runs but link prep does NOT
#      (RULE 2: prep from a stale generation applies stale config);
#   5. the lease is a FIELD of the facts line, so expiry reports immediately.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — standalone_lease_active, tb_ports_readmin_up, link_facts and
#           link_prep_self_heal are sourced from the shipped layer and called
#           as the watcher calls them.
#   STUB  — tb_devices / link_prep_ok / iface_holding_self_ip /
#           repair_link_prep / first_carrier_tb_device (macOS-only wrappers),
#           ifconfig through the CLUSTER_IFCONFIG_BIN seam, sudo as a recording
#           function, and the two parity leaf readers.
#   MIRROR — down_tick reproduces ONLY the watcher's down-branch lease/re-up/
#           prep skeleton; keep it in step with cluster-link-watcher.sh.
#   PIN   — call sites in cluster-link-watcher.sh, cluster-detach.sh and
#           cluster-join.sh, as source: in three of five defects of the 1477
#           family the function was correct and the path that needed it never
#           reached it.
#
# Usage:
#   FACTS=... PARITY=... WATCHER=... DETACH=... JOIN=... bash test-plugged-means-clustered.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

lease_file="$state_dir/standalone-lease"
reup_file="$state_dir/port-reups"
prep_file="$state_dir/link-prep-repairs"
parity_cache="$state_dir/generation-parity"
sudo_log="$state_dir/sudo-calls"
: > "$sudo_log"

# RFC 5737 documentation addresses: this test never touches a real link.
export CLUSTER_STATIC_SELF_IP=192.0.2.2
export CLUSTER_STATIC_PEER_IP=192.0.2.1
export CLUSTER_GENERATION_REPO=example/deploy

# shellcheck disable=SC1090
source "${PARITY:?set PARITY to the path of cluster-generation-parity.sh}"
# shellcheck disable=SC1090
source "${FACTS:?set FACTS to the path of cluster-link-facts.sh}"

# --- stubs -------------------------------------------------------------------
stub_ports=$'en1\nen2'
stub_carrier=""
stub_prep=0
stub_holder=""
stub_repairs=0
tb_devices() { printf '%s\n' "$stub_ports"; }
first_carrier_tb_device() {
  [ -n "$stub_carrier" ] || return 1
  printf '%s' "$stub_carrier"
}
link_prep_ok() { [ "$stub_prep" = 1 ]; }
iface_holding_self_ip() { printf '%s' "$stub_holder"; }
repair_link_prep() {
  stub_repairs=$((stub_repairs + 1))
  return 1
}
generation_local_rev() { printf '%s' "$stub_local_rev"; }
generation_remote_rev() { printf '%s' "$stub_remote_rev"; }
stub_local_rev="aaaaaaaaaaaa"
stub_remote_rev="aaaaaaaaaaaa"
# sudo as a function: tb_ports_readmin_up calls `sudo -n /sbin/ifconfig X up`,
# and a function stub is visible even inside its pipeline subshell.
sudo() { printf '%s\n' "$*" >> "$sudo_log"; }

# ifconfig through the seam. FAKE_UP_DEVS lists admin-up devices (the `<UP` in
# the flags); FAKE_CARRIER_DEV has `status: active`. Admin state and carrier
# are DIFFERENT facts and the code under test must read the right one.
# Shebang is $BASH: a Linux nix sandbox has no /usr/bin/env.
{
  printf '%s\n' "#!$BASH"
  cat << 'FAKE'
case " ${FAKE_UP_DEVS:-} " in
  *" $1 "*) printf '%s: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n' "$1" ;;
  *) printf '%s: flags=8822<BROADCAST,SMART,SIMPLEX,MULTICAST> mtu 1500\n' "$1" ;;
esac
if [ "$1" = "${FAKE_CARRIER_DEV:-}" ]; then
  printf '\tstatus: active\n'
else
  printf '\tstatus: inactive\n'
fi
FAKE
} > "$state_dir/ifconfig"
chmod +x "$state_dir/ifconfig"
export CLUSTER_IFCONFIG_BIN="$state_dir/ifconfig"
export FAKE_UP_DEVS="en1 en2"
export FAKE_CARRIER_DEV=""

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
sudo_calls() { grep -c . "$sudo_log" || true; }
write_lease() { printf '%s\t%s\t%s\n' "$1" created "${2:-test}" > "$lease_file"; }

echo "the lease is the ONE exception, and it expires ON ITS OWN:"
write_lease "$(($(date +%s) + 600))"
check "unexpired lease is active" 0 "$(standalone_lease_active "$lease_file" && echo 0 || echo 1)"
check "and is kept" present "$([ -f "$lease_file" ] && echo present || echo absent)"
write_lease "$(($(date +%s) - 1))"
check "expired lease is NOT active" 1 "$(standalone_lease_active "$lease_file" && echo 0 || echo 1)"
check "an expired lease self-deletes" absent "$([ -f "$lease_file" ] && echo present || echo absent)"
write_lease "forever"
check "a GARBAGE expiry reads as EXPIRED, never as indefinite" 1 \
  "$(standalone_lease_active "$lease_file" && echo 0 || echo 1)"
rm -f "$lease_file"
check "no lease file is no lease" 1 "$(standalone_lease_active "$lease_file" && echo 0 || echo 1)"

echo
echo "THE INCIDENT MECHANISM: an admin-down port is re-upped once no lease holds:"
# cluster-detach admin-downs the cabled port; carrier is unobservable on an
# admin-down port, so nothing carrier-gated could ever fire again.
export FAKE_UP_DEVS="en1"
tb_ports_readmin_up "$reup_file" || true
check "sudo brought the admin-down port up" "-n /sbin/ifconfig en2 up" "$(tail -n1 "$sudo_log")"
check "one attempt counted" 1 "$(cat "$reup_file")"

echo
echo "ports already admin-up: nothing to do, counter cleared:"
export FAKE_UP_DEVS="en1 en2"
: > "$sudo_log"
tb_ports_readmin_up "$reup_file"
check "no sudo call" 0 "$(sudo_calls)"
check "counter cleared" absent "$(cat "$reup_file" 2> /dev/null || echo absent)"

echo
echo "a port that will not come up is BOUNDED (no sudo churn):"
export FAKE_UP_DEVS="en1"
: > "$sudo_log"
export CLUSTER_LINK_PREP_MAX_REPAIRS=3
for _ in 1 2 3 4 5 6; do tb_ports_readmin_up "$reup_file" || true; done
check "stopped at the cap" 3 "$(sudo_calls)"
rm -f "$reup_file"
export FAKE_UP_DEVS="en1 en2"

echo
echo "the watcher's down branch (MIRROR — keep in step with cluster-link-watcher.sh):"
parity_now="state=ok local=a deploy=a"
down_tick() {
  if standalone_lease_active "$lease_file"; then
    :
  else
    tb_ports_readmin_up "$reup_file" || true
    case "$parity_now" in
      *'state=drift'*) : ;;
      *) link_prep_self_heal "$prep_file" || true ;;
    esac
  fi
}

echo "...lease active -> hands off entirely:"
write_lease "$(($(date +%s) + 600))"
export FAKE_UP_DEVS="en1"
: > "$sudo_log"
stub_carrier=en2
stub_repairs=0
down_tick
check "no port re-up under a lease" 0 "$(sudo_calls)"
check "no prep repair under a lease" 0 "$stub_repairs"

echo "...lease expired -> the SAME tick starts driving back to clustered:"
write_lease "$(($(date +%s) - 1))"
down_tick
check "port re-up ran the moment the lease lapsed" 1 "$(sudo_calls)"
check "prep repair ran too (carrier present, prep missing)" 1 "$stub_repairs"

echo "...generation drift -> re-up still runs, link prep does NOT (RULE 2):"
rm -f "$lease_file" "$reup_file"
parity_now="state=drift local=a deploy=b"
: > "$sudo_log"
stub_repairs=0
down_tick
check "re-up still ran under drift" 1 "$(sudo_calls)"
check "but prep repair was refused under drift" 0 "$stub_repairs"
parity_now="state=ok local=a deploy=a"

echo
echo "the lease is a FIELD of the facts line (a flip reports immediately):"
rm -f "$parity_cache"
write_lease "$(($(date +%s) + 600))"
contains "active lease is reported" "lease active" "$(link_facts no "$parity_cache" "$lease_file")"
rm -f "$lease_file"
contains "no lease is reported" "lease none" "$(link_facts no "$parity_cache" "$lease_file")"

echo
echo "call sites (a function nobody calls fixes nothing):"
watcher="${WATCHER:?set WATCHER to the path of cluster-link-watcher.sh}"
detach="${DETACH:?set DETACH to the path of cluster-detach.sh}"
join="${JOIN:?set JOIN to the path of cluster-join.sh}"
pin() {
  local label="$1" file="$2" pattern="$3"
  if grep -v '^[[:space:]]*#' "$file" | grep -Eq "$pattern"; then
    echo "  ok   $label"
  else
    echo "  FAIL $label -> no code line matching /$pattern/ in $file"
    fail=1
  fi
}
pin "the watcher honours the lease on its down path" "$watcher" \
  '(^|[^_[:alnum:]])standalone_lease_active "\$lease_file"'
pin "the watcher re-ups admin-down ports" "$watcher" \
  '(^|[^_[:alnum:]])tb_ports_readmin_up'
pin "the watcher renders the lease in the facts line" "$watcher" \
  'link_facts no "\$gen_parity_file" "\$lease_file"'
pin "the watcher gates link prep on parity (RULE 2)" "$watcher" \
  "state=drift"
pin "cluster-detach RECORDS the lease" "$detach" \
  'standalone-lease'
pin "cluster-detach computes a hard expiry" "$detach" \
  'lease_until=\$\(\(\$\(date \+%s\) \+ lease_secs\)\)'
pin "cluster-detach refuses a non-numeric duration" "$detach" \
  'lease duration'
pin "cluster-join ENDS the lease" "$join" \
  'rm -f "\$state_dir/standalone-lease"'
# Ordering inside the down branch: the lease gate must come BEFORE the re-up,
# or a deliberate detach would be reverted 30s later.
lease_line="$(grep -n 'standalone_lease_active "\$lease_file"' "$watcher" | head -n1 | cut -d: -f1)"
reup_line="$(grep -n 'tb_ports_readmin_up' "$watcher" | head -n1 | cut -d: -f1)"
if [ -n "$lease_line" ] && [ -n "$reup_line" ] && [ "$lease_line" -lt "$reup_line" ]; then
  echo "  ok   the lease gate precedes the port re-up"
else
  echo "  FAIL lease gate (line ${lease_line:-none}) must precede the re-up (line ${reup_line:-none})"
  fail=1
fi

exit "$fail"
