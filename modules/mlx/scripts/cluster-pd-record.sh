# shellcheck shell=bash
# RDMA protection-domain ledger — the WRITE side.
#
# Concatenated after ./cluster-pd-ledger.sh, and ONLY into the two consumers that
# can actually lose a domain: the link watcher (its PD-guard halt fires after N
# failed distributed inits, each of which leaked one) and cluster-detach (which
# escalates to SIGKILL, and a SIGKILLed rank never runs its RDMA teardown).
# cluster-join reads the ledger and never writes it, so it is not given this
# layer — a command that can only refuse cannot also spend.

# Write down protection domains that are now gone.
#
# Appends rather than rewrites: the ledger is an audit trail and each entry names
# which event spent what. Best-effort on I/O, by the same reasoning as
# alert_record — accounting that kills the thing it accounts for is worse than
# accounting that misses a line — but note the read side treats a missing boot
# field as CURRENT, so a partial write still costs a domain rather than hiding
# one.
#
# $1 ledger file, $2 domains lost (integer), $3 source token, $4 free-text detail.
pd_debt_record() {
  local file="$1" domains="$2" source="$3" detail="$4" boot
  case "$domains" in
    '' | *[!0-9]*) domains=1 ;;
  esac
  if [ -z "$file" ]; then
    echo "cluster: WARN no PD ledger configured; $domains leaked protection domain(s) went UNRECORDED ($source: $detail)" >&2
    return 0
  fi
  mkdir -p "$(dirname "$file")" 2> /dev/null || return 0
  # The record is TAB-delimited and the reader parses fields exactly, so a tab or
  # newline inside free text would manufacture fields the reader then trusts.
  # Flattened here, at the one place text enters the ledger, rather than defended
  # against at every read.
  source="${source//$'\t'/ }"
  source="${source//$'\n'/ }"
  detail="${detail//$'\t'/ }"
  detail="${detail//$'\n'/ }"
  boot="$(current_boot_epoch)"
  printf '%s\tboot=%s\tdomains=%s\tsource=%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${boot:-unknown}" "$domains" "$source" "$detail" \
    >> "$file" 2> /dev/null || true
}

# SETTLE THE KICKSTART COUNTER INTO THE LEDGER BEFORE RESETTING IT.
#
# THE HOLE THIS CLOSES. The ledger was introduced because the kickstart counter
# is SESSION-scoped and four separate paths reset it — a settled rank, a link
# cycle, cluster-join, and an accepted manual clear — so a boot could lose
# domains, forget, and lose more without bound. But the ledger was only ever
# WRITTEN at the cap. A counter sitting at 1 or 2 when any of those four resets
# fired was simply deleted, and the domains those attempts had already leaked
# went unrecorded. The accumulation path the ledger exists to close was
# therefore still open one level down: leak two, blip the link, leak two, blip
# again — every guard green, the ledger empty, the kernel steadily poorer.
#
# Not hypothetical. The link probe is a ping of the peer, and a peer that is
# up but not participating (its own watcher halted, or its Local Network
# permission denied so it never leaves `down`) leaves THIS host kickstarting
# into a rendezvous that never forms. Each attempt leaks a domain; a single
# transient link strike then resets the counter before the cap is reached, and
# the loss vanishes from the accounting.
#
# THE INVARIANT THIS ESTABLISHES: rank-kickstarts counts launched attempts whose
# protection-domain cost has NOT yet been written to the ledger. Every path that
# clears it must come through here, so the count is transferred rather than
# discarded. Nothing else may `rm` the file.
#
# WHY IT COUNTS ATTEMPTS AS LEAKS. The counter is incremented only after an
# actual `launchctl kickstart` (a precondition failure consumes no attempt, by
# design), and the watcher only kickstarts when no rank is running — so an
# attempt that was followed by another attempt necessarily failed, and a failed
# `mx.distributed.init()` leaks one domain. $vindicated is subtracted for the
# one caller that has evidence a rank actually settled: there, the final attempt
# succeeded and holds its domain live rather than having leaked it.
#
# Fail-closed on a malformed counter, matching pd_debt_count: an unreadable or
# non-numeric count biases toward recording MORE debt, never less, because
# under-counting is the only direction that lets a start proceed that should
# not have.
#
# $1 ledger file, $2 kickstart counter, $3 vindicated attempts (0 or 1),
# $4 source token, $5 free-text detail.
pd_debt_settle_counter() {
  local debt_file="$1" kicks_file="$2" vindicated="$3" source="$4" detail="$5"
  local kicks leaked
  kicks=0
  if [ -n "$kicks_file" ] && [ -f "$kicks_file" ]; then
    kicks="$(cat "$kicks_file" 2> /dev/null || echo 0)"
  fi
  case "$kicks" in
    '' | *[!0-9]*) kicks=0 ;;
  esac
  case "$vindicated" in
    '' | *[!0-9]*) vindicated=0 ;;
  esac
  leaked=$((kicks - vindicated))
  if [ "$leaked" -gt 0 ]; then
    pd_debt_record "$debt_file" "$leaked" "$source" "$detail"
  fi
  # Cleared LAST and unconditionally: the transfer is the only thing that may
  # precede the reset, and a reset that failed to happen would re-record the
  # same attempts on the next tick.
  [ -n "$kicks_file" ] && rm -f "$kicks_file"
  return 0
}
