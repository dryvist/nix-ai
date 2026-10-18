# shellcheck shell=bash
# Shared wired-limit setter.

# Idempotent wired-ceiling write through the exact-value sudoers grant.
# No-op when unset or already at the target; returns nonzero on failure.
set_wired_limit() {
  local target="$1" current sysctl_bin="${CLUSTER_SYSCTL_BIN:-/usr/sbin/sysctl}"
  local sudo_bin="${CLUSTER_SUDO_BIN:-/usr/bin/sudo}"
  [ -n "$target" ] || return 0
  current="$("$sysctl_bin" -n iogpu.wired_limit_mb 2> /dev/null || echo '')"
  [ "$current" = "$target" ] && return 0
  if "$sudo_bin" -n "$sysctl_bin" -w "iogpu.wired_limit_mb=$target" > /dev/null 2>&1 &&
    [ "$("$sysctl_bin" -n iogpu.wired_limit_mb 2> /dev/null)" = "$target" ]; then
    echo "cluster-link: iogpu.wired_limit_mb=$target"
  else
    echo "cluster-link: WARN failed to set iogpu.wired_limit_mb=$target (sudoers grant missing?)" >&2
    return 1
  fi
}
