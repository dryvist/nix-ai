# shellcheck shell=bash
# Boot scope — what "this boot" means.
#
# One function, concatenated FIRST into every cluster script, because everything
# that expires on a reboot is stamped with it: the halt marker (halt_write /
# halt_drop_if_pre_boot in ./cluster-link-helpers.sh) and the RDMA
# protection-domain ledger (./cluster-pd-ledger.sh, ./cluster-pd-record.sh).
#
# It lives alone rather than inside the helpers because cluster-detach and
# cluster-join need boot scoping and none of the serving helpers around it.
# writeShellApplication runs shellcheck at default severity, where a function
# shipped to a consumer that never calls it is an SC2329 build failure — which is
# what keeps these layers honest instead of letting one grab-bag library grow.

# Seconds since epoch at which this kernel booted, or empty if unavailable.
#
# Anchored on purpose. kern.boottime reads
#   { sec = 1785031601, usec = 233215 } Sat Jul 25 22:06:41 2026
# so an unanchored `.*sec = ` matches through "usec = " and captures the
# MICROSECONDS instead — a value so small that nothing ever looks older than it,
# which silently disables every check built on this.
current_boot_epoch() {
  local sysctl_bin
  # sysctl lives in /usr/sbin, which is NOT on this script's PATH: the module
  # builds it with writeShellApplication, whose PATH is restricted to
  # runtimeInputs (curl, jq, coreutils). A bare `sysctl` therefore produced
  # nothing in the DEPLOYED watcher even though it works in a normal shell, so
  # halt_write recorded boot='unknown', halt_drop_if_pre_boot saw a mismatch on
  # EVERY tick, and EVERY halt was dropped — silently disabling the RDMA PD
  # guard, which is the direct path to protection-domain exhaustion and a
  # mandatory reboot. Observed live 2026-07-26:
  #   halt was recorded under boot '1785031601' but this is boot '1785040009'
  #
  # Resolved through PATH first so a test can stub it, with the absolute OS path
  # as the fallback that is what actually applies in production.
  sysctl_bin="$(command -v sysctl 2> /dev/null || echo /usr/sbin/sysctl)"
  # EMPTY OUTPUT, NEVER A NONZERO STATUS. Every caller already treats empty as
  # "boot unknown" and fails closed on it. Returning nonzero instead would, under
  # writeShellApplication's `set -o errexit -o pipefail`, abort whichever caller
  # assigned the result — turning "boot time unreadable" into "the watcher tick
  # died mid-teardown", which is both worse and far harder to notice. Caught by
  # tests/test-pd-debt.sh, whose unreadable-sysctl case killed the test run
  # outright instead of exercising the fail-closed path it was written for.
  "$sysctl_bin" -n kern.boottime 2> /dev/null | sed -n 's/^{ *sec *= *\([0-9]*\).*/\1/p' || true
}
