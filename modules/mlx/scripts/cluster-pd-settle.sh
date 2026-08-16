# shellcheck shell=bash
# RDMA protection-domain ledger — the COUNTER-SETTLE side.
#
# Concatenated after ./cluster-pd-record.sh, and ONLY into the two consumers
# that RESET the kickstart counter: the link watcher and cluster-join.
#
# Split out of cluster-pd-record.sh rather than living beside pd_debt_record,
# because cluster-detach needs the write side but never resets a counter — and
# a function shipped into a script that cannot call it is dead code the linter
# is right to reject (SC2329). The layer split is the honest fix: each consumer
# is given the operations it actually performs, which is the same rule that
# already keeps the write side away from cluster-join's read-only gate.

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
# attempt that was followed by another attempt necessarily failed. $vindicated
# is subtracted for the one caller that has evidence a rank actually settled:
# there, the final attempt succeeded and holds its domain live rather than
# having leaked it.
#
# NOT EVERY FAILED ATTEMPT ACTUALLY LEAKED, THOUGH. jaccl brings a cluster up in
# two stages (see rank_failure_stage, ./cluster-pd-stage.sh) and ibv_alloc_pd —
# the call that actually consumes a protection domain — lives in the second one.
# An attempt that died in the first (TCP bootstrap: an absent or not-yet-armed
# peer, jaccl's fixed ~15s connect budget) never reached it, and billing it
# anyway protects a budget those attempts could not have spent — the reverse of
# what the fail-closed rule below is for. So $7/$8, if the caller has them, are
# used to check the OUTSTANDING RUN — from $8's baseline to the end of $7 —
# before recording anything: if every attempt in it is provably stage-A-only,
# nothing is billed. Any Stage-B evidence anywhere in that window, or no
# evidence either caller could classify, still bills the full count, unchanged.
#
# Fail-closed on a malformed counter, matching pd_debt_count: an unreadable or
# non-numeric count biases toward recording MORE debt, never less, because
# under-counting is the only direction that lets a start proceed that should
# not have. The stage check above is the same bias in a different shape — it
# can only ever reduce a bill to zero on POSITIVE evidence, never partially.
#
# $1 ledger file, $2 kickstart counter, $3 vindicated attempts (0 or 1),
# $4 source token, $5 free-text detail, $6 cause token (optional; defaults to
# $4 — see pd_debt_record for why the mechanism and the reason are two fields),
# $7 rank stderr log path (optional), $8 byte-offset marker for the start of
# this outstanding run (optional; see cluster-link-watcher.sh — written once
# per run, at its first kickstart, not overwritten by later ones in the same
# run). $7/$8 absent classifies "unknown" (rank_failure_stage's own fail-closed
# default), which bills exactly as if this file predated the stage check.
pd_debt_settle_counter() {
  local debt_file="$1" kicks_file="$2" vindicated="$3" source="$4" detail="$5"
  local cause="${6:-$4}" rank_log="${7:-}" session_offset_file="${8:-}"
  local kicks leaked stage
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
    stage="$(rank_failure_stage "$rank_log" "$session_offset_file")"
    if [ "$stage" = "stage-a" ]; then
      echo "cluster: $leaked attempt(s) outstanding on $source classify stage-a (TCP bootstrap only, across the whole outstanding run) — no protection domain could have been allocated; NOT billed to the ledger" >&2
      leaked=0
    fi
  fi
  if [ "$leaked" -gt 0 ]; then
    pd_debt_record "$debt_file" "$leaked" "$source" "$detail" "$cause"
    # A SILENT TRANSFER WOULD DEFEAT THE POINT. This runs on the reset paths —
    # a link cycle, a settled rank, cluster-join — which are precisely the
    # moments an operator reads as "fine, it recovered". Booking two domains
    # there without saying so reproduces the original defect's *experience*
    # (debt accruing invisibly) even though the accounting is now correct.
    #
    # Reported as a FRACTION of the measured device budget, through the same
    # pd_debt_phrase every other operator surface uses. "2 domains leaked"
    # reads as trivial; "4 of 11 device protection domains consumed until
    # reboot" does not, and 11 is the number that makes it legible.
    echo "cluster: $leaked protection domain(s) charged to the ledger on $source — $(pd_debt_phrase "$(pd_debt_count "$debt_file")" "${CLUSTER_PD_DEBT_MAX:-?}")" >&2
  fi
  # Cleared LAST and unconditionally: the transfer is the only thing that may
  # precede the reset, and a reset that failed to happen would re-record the
  # same attempts on the next tick. session_offset_file goes with it — it
  # describes THIS run, which just ended one way or the other; the next run's
  # first kickstart writes a fresh one.
  [ -n "$kicks_file" ] && rm -f "$kicks_file"
  [ -n "$session_offset_file" ] && rm -f "$session_offset_file"
  return 0
}
