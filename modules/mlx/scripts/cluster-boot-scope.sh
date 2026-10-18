# shellcheck shell=bash
# Boot scope — what "this boot" means.
#
# One function, concatenated FIRST into the responder and lifecycle commands,
# because each published peer-state record is stamped with the current boot.
#
# It lives alone because those consumers need boot scoping without the serving
# helpers used by older cluster automation.
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
  # runtimeInputs. A bare `sysctl` therefore produced nothing in a deployed
  # lifecycle command even though it works in a normal shell. An empty boot
  # stamp would make stale state impossible to distinguish from current state.
  # Observed live 2026-07-26:
  #   halt was recorded under boot '1785031601' but this is boot '1785040009'
  #
  # Resolved through PATH first so a test can stub it, with the absolute OS path
  # as the fallback that is what actually applies in production.
  sysctl_bin="$(command -v sysctl 2> /dev/null || echo /usr/sbin/sysctl)"
  # EMPTY OUTPUT, NEVER A NONZERO STATUS. Every caller already treats empty as
  # "boot unknown" and fails closed on it. Returning nonzero instead would, under
  # writeShellApplication's `set -o errexit -o pipefail`, abort whichever caller
  # assigned the result before it could record the unavailable boot value.
  # The join handshake test covers the stamped peer-state path.
  "$sysctl_bin" -n kern.boottime 2> /dev/null | "${CLUSTER_SED_BIN:-/usr/bin/sed}" -n 's/^{ *sec *= *\([0-9]*\).*/\1/p' || true
}
