#!/usr/bin/env bash
# Memory gates run at J5, after J1 proves no rank is alive and J4 quiesces
# standalone serving. These checks pin free memory, wired headroom, and refusal
# details without depending on the removed watcher state machine.
set -euo pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT
bin="$state_dir/bin"
mkdir -p "$bin"
vmstat_fixture="$state_dir/vmstat-output"
vmstat_rc="$state_dir/vmstat-rc"
sysctl_fixture="$state_dir/sysctl-output"
sysctl_rc="$state_dir/sysctl-rc"

cat > "$bin/vm_stat" << VMSTAT
#!$BASH
forced="\$(cat '$vmstat_rc' 2>/dev/null || true)"
if [ -n "\$forced" ]; then exit "\$forced"; fi
cat '$vmstat_fixture'
VMSTAT
cat > "$bin/sysctl" << SYSCTL
#!$BASH
forced="\$(cat '$sysctl_rc' 2>/dev/null || true)"
if [ -n "\$forced" ]; then exit "\$forced"; fi
cat '$sysctl_fixture'
SYSCTL
chmod +x "$bin/vm_stat" "$bin/sysctl"
export CLUSTER_VMSTAT_BIN="$bin/vm_stat"
export CLUSTER_SYSCTL_BIN="$bin/sysctl"

source modules/mlx/scripts/cluster-room.sh

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
write_vmstat() {
  local page_size="$1" free="$2" inactive="$3" speculative="$4" wired="$5"
  cat > "$vmstat_fixture" << EOFVM
Mach Virtual Memory Statistics: (page size of ${page_size} bytes)
Pages free:                              ${free}.
Pages active:                            1000.
Pages inactive:                          ${inactive}.
Pages speculative:                       ${speculative}.
Pages throttled:                         0.
Pages wired down:                        ${wired}.
Pages purgeable:                         0.
EOFVM
}
reset_state() {
  unset CLUSTER_SHARD_MEMORY_MB CLUSTER_COMPOSITOR_RESERVE_MB
  rm -f "$vmstat_rc" "$sysctl_rc"
  printf '102400\n' > "$sysctl_fixture"
  write_vmstat 16384 0 0 0 0
}
room_verdict() { rank_start_room_ok && echo pass || echo refuse; }

printf '102400\n' > "$sysctl_fixture"
echo '0. unset or zero shard memory disables the gate without reading vm_stat:'
reset_state
export CLUSTER_SHARD_MEMORY_MB=0
check 'zero disables the room gate' pass "$(room_verdict)"
unset CLUSTER_SHARD_MEMORY_MB
check 'unset disables the room gate' pass "$(room_verdict)"

echo '1. free, inactive, and speculative pages count toward shard room:'
reset_state
export CLUSTER_SHARD_MEMORY_MB=1000
write_vmstat 16384 32000 16000 16000 0
check 'exactly enough free plus reclaimable memory passes' pass "$(room_verdict)"

echo '2. an insufficient free-memory reading refuses with the shortfall:'
reset_state
export CLUSTER_SHARD_MEMORY_MB=1000
write_vmstat 16384 6400 0 0 0
check 'short memory refuses' refuse "$(room_verdict)"
mem_headroom_ok 1000 || true
case "$MEM_HEADROOM_DETAIL" in *'100MB free'*'1000MB required'*) echo '  ok   refusal detail names measured and required memory' ;; *) echo "  FAIL refusal detail: $MEM_HEADROOM_DETAIL"; fail=1 ;; esac

echo '3. high wired memory with no live rank is named as an unreclaimed-Metal signature:'
reset_state
export CLUSTER_SHARD_MEMORY_MB=1000
write_vmstat 16384 1600 0 0 64000
mem_headroom_ok 1000 || true
case "$MEM_HEADROOM_DETAIL" in *'unreclaimed-Metal signature'*'only a reboot returns it'*) echo '  ok   refusal detail names the reboot-only recovery' ;; *) echo "  FAIL refusal detail: $MEM_HEADROOM_DETAIL"; fail=1 ;; esac

echo '4. page size comes from vm_stat rather than a fixed 16384:'
reset_state
export CLUSTER_SHARD_MEMORY_MB=1000
write_vmstat 65536 16000 0 0 0
check '65536-byte pages produce the expected 1000MB room' pass "$(room_verdict)"

echo '5. unreadable vm_stat refuses instead of guessing:'
reset_state
export CLUSTER_SHARD_MEMORY_MB=1000
printf '1\n' > "$vmstat_rc"
check 'unreadable memory probe refuses' refuse "$(room_verdict)"
mem_headroom_ok 1000 || true
case "$MEM_HEADROOM_DETAIL" in *'could not read vm_stat'*) echo '  ok   refusal detail names unreadable vm_stat' ;; *) echo "  FAIL refusal detail: $MEM_HEADROOM_DETAIL"; fail=1 ;; esac

echo '6. wired room gate reserves compositor headroom:'
reset_state
export CLUSTER_SHARD_MEMORY_MB=51200
export CLUSTER_COMPOSITOR_RESERVE_MB=16384
write_vmstat 16384 5373952 0 0 3014656
check 'stranded wired pages refuse the start' refuse "$(room_verdict)"
wired_ceiling_room_ok 51200 || true
case "$MEM_HEADROOM_DETAIL" in *'47104MB already wired'*'86016MB start budget'*'REBOOT is the only thing that returns it'*) echo '  ok   wired refusal explains the measured arithmetic and recovery' ;; *) echo "  FAIL wired refusal detail: $MEM_HEADROOM_DETAIL"; fail=1 ;; esac

reset_state
export CLUSTER_SHARD_MEMORY_MB=51200
export CLUSTER_COMPOSITOR_RESERVE_MB=16384
write_vmstat 16384 7864320 0 0 327680
check 'clean-boot wired headroom passes' pass "$(room_verdict)"

reset_state
export CLUSTER_SHARD_MEMORY_MB=90000
export CLUSTER_COMPOSITOR_RESERVE_MB=16384
write_vmstat 16384 7864320 0 0 0
check 'a shard larger than the empty-host budget refuses' refuse "$(room_verdict)"
wired_ceiling_room_ok 90000 || true
case "$MEM_HEADROOM_DETAIL" in *'a reboot will not change it'*'compositorReserveMb'*) echo '  ok   oversized shard is identified as configuration' ;; *) echo "  FAIL config refusal detail: $MEM_HEADROOM_DETAIL"; fail=1 ;; esac

reset_state
export CLUSTER_SHARD_MEMORY_MB=51200
export CLUSTER_COMPOSITOR_RESERVE_MB=16384
write_vmstat 16384 7864320 0 0 327680
printf '1\n' > "$sysctl_rc"
check 'unreadable wired ceiling refuses' refuse "$(room_verdict)"

if [ "$fail" -ne 0 ]; then
  echo 'memory headroom checks FAILED' >&2
  exit 1
fi
echo 'memory headroom checks passed'
