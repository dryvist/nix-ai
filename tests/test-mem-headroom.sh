#!/usr/bin/env bash
# Exercises the memory-headroom rung (mem_stat_mb / mem_headroom_ok /
# mem_headroom_halt_if_persistent, all in modules/mlx/scripts/cluster-link-guards.sh)
# — the precondition that stops a rank starting into a shard that will not fit.
#
# WHY THIS EXISTS. Measured 2026-08-01: a rank started while ~72 GiB of
# unreclaimed wired Metal memory sat on the host from previously-crashed rank
# processes, leaving only ~25 GiB free against a ~49 GiB shard. That failed
# distributed init leaked an RDMA protection domain the same way an errno-60
# timeout does; four retries failed differently and leaked four more, and the
# PD guard's cap halted the host. It happened on BOTH Macs the same afternoon.
# This rung stops the FIRST attempt, and this file is the test that fails if it
# regresses — in particular if it is ever "simplified" into an ordinary failure
# path that consumes a start attempt or charges the PD ledger, which is the
# exact property that makes the rest of the chain impossible.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — mem_stat_mb, mem_headroom_ok, mem_headroom_halt_if_persistent and
#           rank_start_preconditions_ok are all sourced from the shipped
#           script and called as the watcher calls them.
#   STUB  — vm_stat, as a generated executable (not a shell function) on
#           CLUSTER_VMSTAT_BIN, the same reason test-pd-debt.sh generates
#           pgrep/kill rather than shadowing them: the shipped code invokes it
#           through a variable holding a path, so a function would not
#           exercise the same call. Also link_prep_ok / peer_reachable /
#           set_wired_limit / rank_reap_verified (thin macOS wrappers, as in
#           tests/test-rank-start-guards.sh) and curl (alert() payload,
#           mirrors alert-payload-test.sh).
#
# Usage:
#   BOOT_SCOPE=… LEDGER=… HELPERS=… GUARDS=… bash test-mem-headroom.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

halt_file="$state_dir/rank-halted"
latch_file="$state_dir/rank-halt-latched"
kicks_file="$state_dir/rank-kickstarts"
debt_file="$state_dir/pd-debt"
dwell_file="$state_dir/mem-headroom-refused"

export CLUSTER_ROLE=worker
export CLUSTER_STATIC_PEER_IP=192.0.2.1
export CLUSTER_RENDEZVOUS_PORT=11441
export CLUSTER_STATE_FILE="$state_dir/link-state"
export CLUSTER_PD_DEBT_FILE="$debt_file"
export CLUSTER_PD_DEBT_MAX=5
export CLUSTER_PD_DEVICE_BUDGET=11
export CLUSTER_RANK_PROCESS_PATTERN='/mlx_lm\.server'
export CLUSTER_ALERT_URL_FILE="$state_dir/alert-url"
echo "https://hooks.example.invalid/services/T000/B000/fake" > "$CLUSTER_ALERT_URL_FILE"

# shellcheck disable=SC1090
source "${BOOT_SCOPE:?set BOOT_SCOPE to cluster-boot-scope.sh}"
# shellcheck disable=SC1090
source "${LEDGER:?set LEDGER to cluster-pd-ledger.sh}"
# shellcheck disable=SC1090
source "${HELPERS:?set HELPERS to cluster-link-helpers.sh}"
# shellcheck disable=SC1090
source "${GUARDS:?set GUARDS to cluster-link-guards.sh}"

# --- vm_stat stub, generated executable (see header for why not a function) --
bin="$state_dir/bin"
mkdir -p "$bin"
vmstat_fixture="$state_dir/vmstat-output"
vmstat_rc="$state_dir/vmstat-rc"
cat > "$bin/vm_stat" << VMSTAT
#!$BASH
forced="\$(cat '$vmstat_rc' 2>/dev/null || true)"
if [ -n "\$forced" ]; then exit "\$forced"; fi
cat '$vmstat_fixture'
VMSTAT
chmod +x "$bin/vm_stat"
export CLUSTER_VMSTAT_BIN="$bin/vm_stat"

# The device-PD-budget rung (#1442) sits right after this one in the guard
# chain and is out of scope here; stubbed healthy, same pattern as
# rank_reap_verified / generation_parity_cached in test-rank-start-guards.sh.
# Its own refuse/pass matrix is not yet under a dedicated test.
pd_device_budget_ok() { return 0; }

# Writes a vm_stat-shaped fixture. Field order and the trailing "." on every
# count mirror real vm_stat output; mem_stat_mb must parse this shape, not a
# convenient one.
write_vmstat() {
  local page_size="$1" free="$2" inactive="$3" speculative="$4" wired="$5"
  cat > "$vmstat_fixture" << EOF
Mach Virtual Memory Statistics: (page size of ${page_size} bytes)
Pages free:                              ${free}.
Pages active:                            1000.
Pages inactive:                          ${inactive}.
Pages speculative:                       ${speculative}.
Pages throttled:                         0.
Pages wired down:                        ${wired}.
Pages purgeable:                         0.
"Translation faults":                    123456.
Pages copy-on-write:                     0.
Pages zero filled:                       0.
Pages reactivated:                       0.
Pages purged:                            0.
File-backed pages:                       0.
Anonymous pages:                         0.
Pages stored in compressor:              0.
Pages occupied by compressor:            0.
Decompressions:                          0.
Compressions:                            0.
Pageins:                                 0.
Pageouts:                                0.
Swapins:                                 0.
Swapouts:                                0.
EOF
}

# --- stubs for the other rungs and macOS-only wrappers (see test-rank-start-guards.sh) ---
link_prep_ok() { return 0; }
peer_reachable() { return 0; }
set_wired_limit() { return 0; }
rank_reap_verified() { return 0; }
hostname() { echo test-host; }
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
reset_state() {
  rm -f "$halt_file" "$latch_file" "$kicks_file" "$debt_file" "$dwell_file" "$vmstat_rc"
  : > "$curl_log"
  unset CLUSTER_RANK_START_ALIGN_SECS CLUSTER_SHARD_MEMORY_MB CLUSTER_MEM_HEADROOM_DWELL_TICKS
  write_vmstat 16384 0 0 0 0
}
kicks_now() { cat "$kicks_file" 2> /dev/null || echo absent; }
halt_cause() { sed -n 's/.*cause=\([^	]*\).*/\1/p' "$halt_file" 2> /dev/null || echo none; }
verdict() { rank_start_preconditions_ok >&2 && echo start || echo "$PRECONDITION_REASON"; }

echo "0. the rung is disabled with 0/unset, no vm_stat read needed to pass:"
reset_state
write_vmstat 16384 0 0 0 0 # zero free, would refuse if the rung ran
export CLUSTER_SHARD_MEMORY_MB=0
check "unset/0 required disables the rung" start "$(verdict)"
unset CLUSTER_SHARD_MEMORY_MB
check "unset entirely is the same as 0" start "$(verdict)"

echo "1. sufficient free+reclaimable memory allows the start:"
reset_state
export CLUSTER_SHARD_MEMORY_MB=1000
# 1000MB at 16384-byte pages = 64000 pages; split across free/inactive/speculative
# to prove all three are summed, not just "Pages free".
write_vmstat 16384 32000 16000 16000 0
check "mem_headroom_ok passes at exactly enough (free+inactive+speculative)" 0 \
  "$(mem_headroom_ok 1000 && echo 0 || echo 1)"
check "the full precondition chain proceeds to start" start "$(verdict)"

echo "2. insufficient memory refuses the start, and consumes NOTHING:"
# THE PROPERTY THAT MAKES THE PD-EXHAUSTION CHAIN IMPOSSIBLE. A refusal here
# must be free in the same currency the PD guard protects — no kickstart
# attempt, no ledger charge — exactly like every other rung in
# rank_start_preconditions_ok. This must fail loudly if that ever regresses
# into an ordinary failure path.
reset_state
export CLUSTER_SHARD_MEMORY_MB=1000
write_vmstat 16384 6400 0 0 0 # 100MB free, 900MB short
check "start is blocked" insufficient-memory "$(verdict)"
check "no attempt consumed" absent "$(kicks_now)"
check "nothing charged to the PD ledger" 0 "$(pd_debt_count "$debt_file")"
check "no halt marker written on a single refusal" missing \
  "$([ -f "$halt_file" ] && echo latched || echo missing)"

echo "   ...and the detail names the shortfall in MB:"
mem_headroom_ok 1000 || true
check "detail states the free MB against the requirement" yes \
  "$(case "$MEM_HEADROOM_DETAIL" in *"100MB free"*) echo yes ;; *) echo no ;; esac)"

echo "3. the unreclaimed-Metal signature is named when wired covers the requirement:"
# Log-only — this must never change the verdict, only explain it. By the time
# this rung runs, rung 0b (rank_reap_verified, stubbed true here) has already
# proven no rank process survives, so high wired with nothing left to hold it
# is the leak signature from the 2026-08-01 incident, not a live session.
reset_state
export CLUSTER_SHARD_MEMORY_MB=1000
write_vmstat 16384 1600 0 0 64000 # 25MB free, 1000MB wired (matches the incident shape)
mem_headroom_ok 1000 || true
check "detail names the unreclaimed-Metal signature" yes \
  "$(case "$MEM_HEADROOM_DETAIL" in *"unreclaimed-Metal signature"*) echo yes ;; *) echo no ;; esac)"
check "still refuses (log-only never flips the verdict)" 1 "$(mem_headroom_ok 1000 && echo 0 || echo 1)"

echo "4. page size is READ from vm_stat, never assumed 16384:"
# A hardcoded 16384 would compute this as 250MB (below 1000) and wrongly
# refuse; the real page size (65536, 4x larger) computes exactly 1000MB.
reset_state
export CLUSTER_SHARD_MEMORY_MB=1000
write_vmstat 65536 16000 0 0 0 # 16000 pages * 65536 bytes / 1048576 = 1000MB
check "the real (non-16384) page size is used, not a hardcoded one" start "$(verdict)"

echo "4b. a VERBATIM real vm_stat capture parses correctly (not a hand-built fixture):"
# write_vmstat above is a template written from memory of the format; a
# reproduction written from the same mental model as the code under test can
# share that model's own gaps. This is a byte-for-byte capture (macOS,
# 2026-08-01, `vm_stat > fixture`) frozen as a literal, so the awk field
# splitting is exercised against the real thing, not a paraphrase of it.
# Expected MB figures are independently cross-checked by hand below the
# assertion, not merely "whatever the code currently outputs".
cat > "$vmstat_fixture" << 'REALVMSTAT'
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                  2639858.
Pages active:                                1164841.
Pages inactive:                              1116526.
Pages speculative:                             53146.
Pages throttled:                                   0.
Pages wired down:                            3348211.
Pages purgeable:                               69080.
"Translation faults":                       72587661.
Pages copy-on-write:                         7850919.
Pages zero filled:                         111307069.
Pages reactivated:                             69193.
Pages purged:                                 402130.
File-backed pages:                            496308.
Anonymous pages:                             1838205.
Pages stored in compressor:                    17979.
Pages occupied by compressor:                   5321.
Decompressions:                                 8893.
Compressions:                                  30403.
Pageins:                                    10264647.
Pageouts:                                        192.
Swapins:                                           0.
Swapouts:                                          0.
REALVMSTAT
# By hand: free_mb = (2639858+1116526+53146)*16384/1048576 = 59523
#          wired_mb = 3348211*16384/1048576 = 52315
check "mem_stat_mb on a verbatim real capture" "59523 52315" "$(mem_stat_mb)"

echo "5. an unreadable vm_stat refuses rather than guessing (fails closed):"
reset_state
export CLUSTER_SHARD_MEMORY_MB=1000
printf '1\n' > "$vmstat_rc"
check "start is blocked" insufficient-memory "$(verdict)"
check "no attempt consumed" absent "$(kicks_now)"
mem_headroom_ok 1000 || true
check "an unreadable probe says so, not a fabricated number" yes \
  "$(case "$MEM_HEADROOM_DETAIL" in *"could not read vm_stat"*) echo yes ;; *) echo no ;; esac)"
rm -f "$vmstat_rc"

echo "6. one refused tick does NOT halt; sustained refusal does:"
reset_state
export CLUSTER_SHARD_MEMORY_MB=1000
export CLUSTER_MEM_HEADROOM_DWELL_TICKS=3
write_vmstat 16384 6400 0 0 0 # 100MB free, always short
mem_headroom_halt_if_persistent "$halt_file" "$latch_file" "$dwell_file"
check "tick 1: no halt yet" missing "$([ -f "$halt_file" ] && echo latched || echo missing)"
check "dwell counted" 1 "$(cat "$dwell_file")"
mem_headroom_halt_if_persistent "$halt_file" "$latch_file" "$dwell_file"
check "tick 2: still no halt" missing "$([ -f "$halt_file" ] && echo latched || echo missing)"
mem_headroom_halt_if_persistent "$halt_file" "$latch_file" "$dwell_file"
check "tick 3 (the configured dwell): halts" insufficient-memory-persistent "$(halt_cause)"
check "a page went out" 1 "$(alerts)"
check "still no attempt consumed anywhere in this" absent "$(kicks_now)"
check "still nothing charged to the PD ledger" 0 "$(pd_debt_count "$debt_file")"

echo "   ...and composes with the auto-reboot cause gate:"
# pd_auto_reboot_if_warranted must recognize this cause the same way it
# already recognizes pd-debt-exhausted and rank-start-failures — this is the
# seam the memory rung was asked to compose with, not a reimplementation of it.
reboot_log="$state_dir/reboot-log"
sudo() {
  printf '%s\n' "$*" >> "$reboot_log"
}
fdesetup() { [ "$1" = status ] && echo "FileVault is Off."; }
export CLUSTER_PD_AUTO_REBOOT_WINDOW_SECS=21600
pd_auto_reboot_if_warranted "$halt_file" "$state_dir/pd-auto-reboot-last" up
check "the memory halt is accepted by the reboot gate" 1 "$(wc -l < "$reboot_log" | tr -d ' ')"

echo "7. recovery: once memory is sufficient again, the dwell counter resets:"
reset_state
export CLUSTER_SHARD_MEMORY_MB=1000
export CLUSTER_MEM_HEADROOM_DWELL_TICKS=3
write_vmstat 16384 6400 0 0 0
mem_headroom_halt_if_persistent "$halt_file" "$latch_file" "$dwell_file"
mem_headroom_halt_if_persistent "$halt_file" "$latch_file" "$dwell_file"
check "two refusals counted, no halt yet" 2 "$(cat "$dwell_file")"
write_vmstat 16384 64000 0 0 0 # now plenty free
mem_headroom_halt_if_persistent "$halt_file" "$latch_file" "$dwell_file"
check "dwell file cleared on recovery" absent "$([ -f "$dwell_file" ] && echo present || echo absent)"
write_vmstat 16384 6400 0 0 0 # short again
mem_headroom_halt_if_persistent "$halt_file" "$latch_file" "$dwell_file"
check "recovery reset the count, not just capped it" 1 "$(cat "$dwell_file")"

exit "$fail"
