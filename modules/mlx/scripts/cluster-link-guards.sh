# shellcheck shell=bash
# Cluster link watcher — rank-start guards and the halt latch.
#
# Function definitions ONLY (no top-level statements), concatenated ahead of
# cluster-link-watcher.sh with cluster-link-helpers.sh,
# cluster-link-locate.sh and cluster-link-repair.sh. Marker paths are passed as
# ARGUMENTS rather than read from the watcher's scope, so each function is
# callable — and testable — on its own.
#
# WHY THIS FILE EXISTS. Start order is load-bearing and until 2026-07-25 nothing
# enforced it. Each host's watcher converges independently, so a worker whose
# coordinator has no rank yet will kickstart into a rendezvous that does not
# exist:
#
#   RuntimeError: [jaccl] Couldn't connect (error: 60)   # errno 60 = ETIMEDOUT
#   ... 3 attempts, PD guard HALTS ...
#   ValueError: [jaccl] Changing queue pair to RTR failed with errno 96
#
# Every failed mx.distributed.init() leaks a kernel RDMA Protection Domain and
# exhaustion is reboot-only. A worker hammering an absent peer therefore converts
# a trivially recoverable situation (peer not up yet — wait) into a mandatory
# reboot. It did exactly that on 2026-07-24.
#
# Consumed environment:
#   CLUSTER_ROLE                     coordinator | worker
#   CLUSTER_STATIC_PEER_IP           peer's link address; for a worker the peer
#                                  IS the coordinator, which is why the
#                                  rendezvous probe needs no second address
#   CLUSTER_RENDEZVOUS_PORT          JACCL rendezvous port (MLX_JACCL_COORDINATOR)
#   CLUSTER_PEER_PROBE_TIMEOUT_SECS  bound on the rendezvous TCP connect
#   CLUSTER_LINK_REPAIR              1 = attempt link-prep repair when this
#                                  host holds no link address
#   CLUSTER_LINK_ACTIVATE_TIMEOUT_SECS  bound on the activation repair fallback
#   CLUSTER_WIRED_LIMIT_MB           optional cluster wired ceiling

# Unattended repair for a host that came up WITHOUT its link address.
#
# A boot does not produce a usable link. nix-darwin's cluster-link prep runs in
# root postActivation, which fires before Thunderbolt carrier settles, so the
# prep pass can find no carrier-active port and therefore address nothing —
# observed 2026-07-24 on the coordinator: en2 had carrier, activation had run,
# and no interface held the link address at all. Re-running `activate` fixed it
# and logged `[cluster-link-prep] set <ip> on en2 (carrier active)`. The rank
# started in that window died with `[jaccl] Couldn't bind socket (error: 49)` —
# errno 49 is EADDRNOTAVAIL, i.e. exactly this missing address.
#
# Direct repair goes FIRST here (unlike cluster-join, which prefers activation
# for persistence): this runs on a 30s watcher tick, and the direct grant is the
# same ifconfig alias the prep pass would apply, without a full activation's
# blast radius. Activation is the bounded fallback.
repair_link_prep() {
  local activate_timeout="${CLUSTER_LINK_ACTIVATE_TIMEOUT_SECS:-0}"
  echo "cluster-link: repairing link prep ($CLUSTER_STATIC_SELF_IP absent; direct granted alias)"
  repair_link_direct || true
  if link_prep_ok; then
    echo "cluster-link: link prep repaired ($CLUSTER_STATIC_SELF_IP on $(iface_holding_self_ip))"
    return 0
  fi
  if [ "$activate_timeout" -gt 0 ]; then
    echo "cluster-link: direct repair did not restore prep; re-running activation (bounded ${activate_timeout}s)"
    timeout "$activate_timeout" sudo -n /nix/var/nix/profiles/system/activate > /dev/null 2>&1 || true
    if link_prep_ok; then
      echo "cluster-link: link prep repaired by activation ($CLUSTER_STATIC_SELF_IP on $(iface_holding_self_ip))"
      return 0
    fi
  fi
  echo "cluster-link: WARN link prep still broken; $CLUSTER_STATIC_SELF_IP is on no carrier-active Thunderbolt port outside bridge0. Is the cable seated?" >&2
  return 1
}

# A "is rank 0 listening?" rendezvous probe used to live here and gate every
# worker rank start. It was removed 2026-07-25: the gate was the reason the
# cluster never formed unattended. Waiting for rank 0 to listen guarantees the
# worker reaches distributed init ~20-30s later than the coordinator, which is
# far outside jaccl's fixed ~15s connect budget, so the coordinator has always
# exited by the time the worker dials. Ranks are now aligned to a shared start
# boundary instead of ordered — see rung 2 below.

# Everything that must hold before a rank start is allowed to CONSUME a start
# attempt. Nonzero return = do not start, do not count it.
#
# "Do not count it" is the whole point, and there is precedent: the wired-ceiling
# check (folded in below, rung 3) has always skipped the start without consuming
# an attempt. A precondition that is not yet satisfied is not a failed start —
# it leaks no protection domain — so counting it would spend the PD guard's
# budget on a situation that costs nothing, and the guard's budget is the thing
# standing between a missing peer and a forced reboot.
#
# Sets PRECONDITION_REASON to a stable cause token for the halt marker.
rank_start_preconditions_ok() {
  local pd_max pd_debt
  PRECONDITION_REASON=""
  # 0. THE LEDGER MUST BE WIRED UP. Rungs 0a and 0b below are the only things
  #    standing between a leaked protection domain and an unbounded accumulation
  #    of them, and both are driven entirely by environment this module bakes at
  #    eval. An absent variable would make them silently inert — which is the
  #    single most repeated defect in this subsystem's history (a sysctl off the
  #    sanitized PATH disabled the halt marker; a stale process pattern disabled
  #    a reap; both reported success throughout). So a missing setting is a
  #    refusal, not a default. Nothing is launched, so nothing leaks, so no
  #    attempt is consumed and the next tick retries.
  if [ -z "${CLUSTER_PD_DEBT_MAX:-}" ] || [ -z "${CLUSTER_PD_DEBT_FILE:-}" ] ||
    [ -z "${CLUSTER_RANK_PROCESS_PATTERN:-}" ]; then
    PRECONDITION_REASON="pd-guard-unconfigured"
    echo "cluster-link: PD guard is not fully configured (need CLUSTER_PD_DEBT_MAX, CLUSTER_PD_DEBT_FILE and CLUSTER_RANK_PROCESS_PATTERN); NOT starting the rank rather than starting one it cannot protect (no attempt consumed)" >&2
    return 1
  fi
  # 0a. PROTECTION-DOMAIN DEBT. Every domain this boot is known to have leaked is
  #     in the ledger; at the cap the rank does not start. This is the proactive
  #     half of the guard — the kickstart counter below only reacts once errno 96
  #     proves the domains are already gone, and by then a reboot is mandatory.
  pd_max="${CLUSTER_PD_DEBT_MAX}"
  case "$pd_max" in
    '' | *[!0-9]*) pd_max=0 ;;
  esac
  if [ "$pd_max" -gt 0 ]; then
    pd_debt="$(pd_debt_count "$CLUSTER_PD_DEBT_FILE")"
    pd_debt="${pd_debt:-0}"
    if [ "$pd_debt" -ge "$pd_max" ]; then
      PRECONDITION_REASON="pd-debt-exhausted"
      echo "cluster-link: $(pd_debt_phrase "$pd_debt" "$pd_max"); NOT starting the rank. Only a reboot returns a leaked domain — clearing markers will not." >&2
      return 1
    fi
  fi
  # 0b. NO SURVIVING RANK. Never start a rank while another still holds an RDMA
  #     context. launchd reporting the agent as not running is not evidence: a
  #     re-parented or SIGKILL-orphaned engine keeps its protection domain, and
  #     starting a second rank over it is how debt accumulates across restarts.
  #     rank_reap_verified SIGTERMs a survivor and re-verifies; it returns
  #     success only when absence is PROVEN, so an unanswerable probe blocks the
  #     start too. Nothing was launched, so no attempt is consumed.
  if ! rank_reap_verified; then
    PRECONDITION_REASON="rank-survivor"
    echo "cluster-link: a previous rank process could not be confirmed gone; NOT starting the rank (no attempt consumed)" >&2
    return 1
  fi
  # 1. This host must hold its own link address. A boot does not guarantee one
  #    (see repair_link_prep): the rank would die with errno 49 EADDRNOTAVAIL.
  if ! link_prep_ok; then
    PRECONDITION_REASON="link-address-missing"
    echo "cluster-link: this host holds no carrier-active link address; NOT starting the rank (no attempt consumed)" >&2
    if [ "${CLUSTER_LINK_REPAIR:-1}" = "1" ]; then
      repair_link_prep || true
    fi
    return 1
  fi
  # 2. BOTH ROLES: hold until the next shared wall-clock start boundary, so the
  #    two ranks reach distributed init together.
  #
  #    This replaced a worker-only "rank 0 must already be listening" gate, which
  #    was the direct cause of the cluster never forming unattended. jaccl's
  #    client connect budget is hardcoded at ~15s (backoff 1s, 2s, 4s, 8s); the
  #    library exposes no knob to raise it — the only variables it reads are the
  #    coordinator address, ibv device list, rank index, and ring flag. But a
  #    rank needs ~20-30s of dependency resolution, interpreter start and mlx
  #    import before it reaches distributed init. So a worker that started the
  #    moment it saw rank 0 listening arrived ~20-30s late, by which point the
  #    coordinator had exhausted its own wait and exited, and the worker dialled
  #    a dead port: errno 60, ETIMEDOUT. Waiting for the coordinator GUARANTEED
  #    the worker was too late. Measured 2026-07-25 — sequential starts oscillate
  #    (ranks alternate, never overlap) and both die within ~6 min, while
  #    starting both in the same second held 200+s and served real tokens.
  #
  #    Alignment, not ordering, is what makes this work: there is no leader to
  #    wait for. Both hosts compute the same boundary from an NTP-synced clock
  #    and sleep to it, so they fire within about a second of each other.
  #
  #    The period MUST exceed the tick (enforced by the >= 2 multiple in
  #    rankStartAlignMultiple). At exactly one tick, two hosts whose ticks fall
  #    either side of a boundary map to different boundaries and never converge.
  align="${CLUSTER_RANK_START_ALIGN_SECS:-0}"
  if [ "$align" -gt 0 ]; then
    remainder=$(( $(date +%s) % align ))
    if [ "$remainder" -ne 0 ]; then
      echo "cluster-link: holding $((align - remainder))s for the shared rank-start boundary (both ranks must reach rendezvous inside jaccl's fixed connect budget)"
      sleep "$((align - remainder))"
    fi
  fi
  # 3. Never start a rank over a standalone-sized ceiling: a shard wiring out
  #    the GUI working set is the 2026-07-12 dual-host panic.
  if ! set_wired_limit "${CLUSTER_WIRED_LIMIT_MB:-}"; then
    PRECONDITION_REASON="wired-ceiling"
    echo "cluster-link: wired ceiling not applied; NOT starting the rank (no attempt consumed)"
    return 1
  fi
  return 0
}

# HALT AT THE RESERVE, NOT AT EXHAUSTION.
#
# The kickstart counter below is the reactive half of the PD guard: it halts once
# N distributed inits have already failed, i.e. once N protection domains are
# already gone and errno 96 is the proof. This is the proactive half. It reads
# the boot-scoped ledger of domains ALREADY known lost (./cluster-pd-ledger.sh)
# and halts while there are still domains left to protect.
#
# THE CAP IS A RESERVE, NOT A DISTANCE FROM EXHAUSTION. The device budget is 11
# (measured max_pd, ibv_devinfo -v; the ~60 sessions ml-explore/mlx#3207 quotes
# are other hardware). A working cluster session must itself allocate protection
# domains, and max_qp and max_cq are 11 too — a live session draws on three
# equally scarce pools at once. Free domains are not observable either: the
# device reports its maximum, never its current allocation, and other processes
# may hold some, so what is left is unknown and at most (11 - leaked). Burning 10
# of 11 on failed attempts would satisfy "not yet exhausted" and still leave the
# attempt that mattered with nothing to allocate. The cap therefore stops at 5,
# holding six domains back for the session we actually want.
#
# It closes the accumulation path the counter cannot: the counter is
# SESSION-scoped, so a link cycle, a settled rank or a cluster-join all reset it,
# and a boot could therefore lose three domains, forget, lose three more, without
# bound. The ledger is BOOT-scoped, so a reboot — the one event that actually
# returns a domain — is the only thing that lifts this halt. No second marker
# scheme: the same boot= field the halt marker already uses is the mechanism.
#
# Always returns 0 so it composes into the watcher's existing
# `halt_drop_if_pre_boot … && [ -f "$halt_file" ]` chain without a new branch.
# Logs and pages exactly once per halt — it runs on every tick.
#
# $1 halt marker, $2 latch, $3 ledger file.
pd_debt_halt_if_exhausted() {
  local halt_file="$1" latch_file="$2" debt_file="$3" max debt
  max="${CLUSTER_PD_DEBT_MAX:-0}"
  case "$max" in
    '' | *[!0-9]*) return 0 ;;
  esac
  if [ "$max" -le 0 ]; then
    return 0
  fi
  debt="$(pd_debt_count "$debt_file")"
  debt="${debt:-0}"
  if [ "$debt" -lt "$max" ]; then
    return 0
  fi
  if [ -f "$halt_file" ]; then
    return 0
  fi
  echo "cluster-link: $(pd_debt_phrase "$debt" "$max"); HALTING rank starts before the kernel runs out. A leaked domain is returned only by a reboot." >&2
  halt_write "$halt_file" "$latch_file" "pd-debt-exhausted" \
    "$(pd_debt_phrase "$debt" "$max"); reboot required to return them"
  alert "$(hostname -s): $(pd_debt_phrase "$debt" "$max"). Rank starts are halted at the cap, which RESERVES the rest of the device budget for a session that can actually succeed — not at exhaustion, and not after errno 96. Reboot this host to return the domains — clearing the marker will not, and the guard re-halts on the ledger's own evidence." \
    "mlx-cluster PD debt at cap"
  return 0
}

# Decide whether a by-hand clear of the halt marker may stand.
#
# On 2026-07-24 the PD guard fired correctly at three consecutive failures, and a
# human then deleted the marker to force a retry on an unverified hypothesis —
# burning the remaining protection domains and making the reboot mandatory. The
# design invited it: the halt was just a file, and the docs said "rm the marker
# or replug".
#
# So a clear is now a REQUEST, not a fact. It stands only if the preconditions
# actually pass; otherwise the halt is rewritten and the operator is told which
# cause is still failing. Accepting a clear also resets the attempt counter,
# because leaving it at the cap would re-halt on the very next tick and make the
# documented recovery a no-op.
#
# $1 halt marker, $2 latch, $3 kickstart counter. 0 = clear accepted.
halt_clear_accepted() {
  local halt_file="$1" latch_file="$2" kicks_file="$3" prior
  prior="$(cat "$latch_file" 2> /dev/null || echo unknown)"
  if rank_start_preconditions_ok; then
    echo "cluster-link: halt marker cleared by hand and preconditions RE-VERIFIED (prior cause: $prior); allowing one retry"
    rm -f "$latch_file" "$kicks_file"
    return 0
  fi
  echo "cluster-link: halt marker cleared by hand but preconditions still fail ($PRECONDITION_REASON); RE-HALTING — a manual clear must not re-burn RDMA protection domains" >&2
  halt_write "$halt_file" "$latch_file" "manual-clear-rejected" \
    "prior=$prior still-failing=$PRECONDITION_REASON"
  return 1
}
