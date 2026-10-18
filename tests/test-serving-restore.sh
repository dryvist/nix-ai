#!/usr/bin/env bash
# The shared restore function returns coordinator agents and worker hooks.
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/LaunchAgents"
write_stub() {
  printf '#!%s\n' "$BASH" > "$1"
  cat >> "$1"
}

write_stub "$tmp/bin/launchctl" <<'LAUNCHCTL'
printf '%s\n' "$*" >> "$FAKE_LAUNCHCTL_LOG"
case "$1" in
  print) [ -f "$FAKE_DIR/${2##*/}.loaded" ] ;;
  bootstrap)
    [ "${FAKE_BOOTSTRAP_FAILS:-0}" = 1 ] && exit 1
    label="${3##*/}"
    label="${label%.plist}"
    touch "$FAKE_DIR/$label.loaded"
    ;;
esac
LAUNCHCTL
chmod +x "$tmp/bin/launchctl"
export PATH="$tmp/bin:$PATH"
export FAKE_DIR="$tmp"
export FAKE_LAUNCHCTL_LOG="$tmp/launchctl.log"

source modules/mlx/scripts/cluster-serving-restore.sh

fail=0
check() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then echo "  ok   $label -> $got"; else echo "  FAIL $label -> got '$got', want '$want'"; fail=1; fi
}

export CLUSTER_LAUNCHCTL_BIN="$tmp/bin/launchctl"
export CLUSTER_SH_BIN="$BASH"
export CLUSTER_LAUNCH_AGENTS_DIR="$tmp/LaunchAgents"
export CLUSTER_SERVER_LABELS='dev.test.api dev.test.worker'
export CLUSTER_WATCHDOG_LABEL=dev.test.watchdog
export CLUSTER_WATCHDOG_PLIST="$tmp/LaunchAgents/dev.test.watchdog.plist"
touch "$CLUSTER_LAUNCH_AGENTS_DIR/dev.test.api.plist" "$CLUSTER_LAUNCH_AGENTS_DIR/dev.test.worker.plist" "$CLUSTER_WATCHDOG_PLIST"

export CLUSTER_ROLE=coordinator
if restore_normal_serving; then rc=0; else rc=$?; fi
check 'coordinator restore succeeds' 0 "$rc"
check 'resident server bootstrapped' yes "$(grep -Fq "$CLUSTER_LAUNCH_AGENTS_DIR/dev.test.api.plist" "$FAKE_LAUNCHCTL_LOG" && echo yes || echo no)"
check 'watchdog bootstrapped' yes "$(grep -Fq "$CLUSTER_WATCHDOG_PLIST" "$FAKE_LAUNCHCTL_LOG" && echo yes || echo no)"

: > "$FAKE_LAUNCHCTL_LOG"
rm -f "$tmp/dev.test.api.loaded"
export FAKE_BOOTSTRAP_FAILS=1
if restore_normal_serving; then rc=0; else rc=$?; fi
check 'failed coordinator bootstrap propagates' 1 "$rc"
unset FAKE_BOOTSTRAP_FAILS

export CLUSTER_ROLE=worker
export CLUSTER_RESTORE_CMD="printf restored > '$tmp/restore-ran'"
if restore_normal_serving; then rc=0; else rc=$?; fi
check 'worker restore hook succeeds' 0 "$rc"
check 'worker restore hook ran' restored "$(cat "$tmp/restore-ran")"

unset CLUSTER_RESTORE_CMD
export CLUSTER_QUIESCE_CMD=true
if restore_normal_serving; then rc=0; else rc=$?; fi
check 'worker cannot quiesce without a restore hook' 1 "$rc"

unset CLUSTER_QUIESCE_CMD
if restore_normal_serving; then rc=0; else rc=$?; fi
check 'worker with no quiesce has nothing to restore' 0 "$rc"

if [ "$fail" -ne 0 ]; then echo 'serving restore checks FAILED' >&2; exit 1; fi
echo 'serving restore checks passed'
