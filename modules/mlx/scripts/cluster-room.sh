# shellcheck shell=bash
# Shared cluster room gates.

# Free-ish and wired memory this host currently holds, in MB, from ONE vm_stat
# read: prints "<free_mb> <wired_mb>" on stdout, nothing and nonzero on any
# parse failure.
#
# Free-ish = free pages plus what the kernel can reclaim without paging
# anything out (inactive + speculative) — NEVER wired down. WHY FREE, NOT
# WIRED, DECIDES WHETHER A SHARD FITS: the question is whether room exists for
# a NEW shard, and only free + reclaimable can answer that. Memory a live rank
# already holds is, correctly, not free.
#
# THE ORIGINAL NOTE HERE WAS RIGHT; A "CORRECTION" ON 2026-08-01 WAS NOT.
# The original said MLX holds a loaded shard's weights in ordinary resident
# memory rather than wired, citing a ~49 GiB shard serving real tokens at only
# ~3.5 GiB wired. That was briefly replaced with the opposite claim — that a
# healthy rank wires its whole shard. The replacement is retracted here.
#
# Measured on the coordinator while it was demonstrably serving: a real
# completion, 32 generated tokens, not a /v1/models probe.
#
#   Pages wired down    3.1 GiB     <- the shard is NOT here
#   Anonymous pages    53.1 GiB     <- the shard IS here
#   File-backed        21.6 GiB
#   rank process        rss ~0, vsz ~415 GiB   (mmap'd; RSS underreports too)
#
# So a healthy serving rank sits near 3 GiB wired while holding ~50 GiB of
# shard as ANONYMOUS memory. Both halves of the original note stand: a low
# wired figure says nothing about what is loaded, and a high one is the
# unreclaimed-Metal leak signature — wired memory left with no owning
# process, high enough that the compositor, drawing from the same pool, can
# be starved of command buffers.
#
# HOW THE BAD CORRECTION HAPPENED, recorded so it is not repeated. A ~50 GiB
# wired reading on the worker was assumed to be "the shard resident". It was
# not a healthy serving rank; wired that high is the leak signature described
# above. Two different quantities were then compared as if they were one: a
# TOTAL footprint model (weights + buffers + KV, which does approach the host
# ceiling) and `Pages wired down` (which does not). Establish which quantity a
# number measures before reasoning about a threshold on it.
#
# WHAT THIS DOES AND DOES NOT SAY ABOUT A RUNTIME WIRED GUARD. A guard of that
# kind was added and removed on 2026-08-01. It was removed because it was
# introduced without evidence and justified by the conflation above — not
# because the measurements rule one out. On these numbers, healthy (~3 GiB) and
# leaked (~50-96 GiB) are in fact widely separated. Whether a wired-thresholded
# runtime guard is worth having is therefore OPEN, and would need its own
# design and evidence rather than a heuristic.
#
# `--list-devices`'s own free-memory report is per-process fiction — it claimed
# 102399 MiB free on a host actually holding 68 GiB wired — so this reads
# vm_stat directly rather than trusting MLX's numbers.
#
# Page size is READ from vm_stat's own header line, never assumed: a
# hardcoded 16384 silently breaks the day Apple changes it, or on hardware
# with a different page size.
#
# CLUSTER_VMSTAT_BIN is a test seam, like CLUSTER_NETSTAT_BIN /
# CLUSTER_PGREP_BIN / CLUSTER_KILL_BIN — vm_stat is not on a
# writeShellApplication PATH.
mem_stat_mb() {
  local out page_size free inactive speculative wired v
  out="$("${CLUSTER_VMSTAT_BIN:-/usr/bin/vm_stat}" 2> /dev/null)" || return 1
  page_size="$(printf '%s\n' "$out" | sed -n 's/.*page size of \([0-9][0-9]*\) bytes.*/\1/p')"
  # $(NF-1), not a fixed column: "Pages wired down" is three words where every
  # other counter here is two, so a fixed $3 silently reads "down" instead of
  # the count on that one line alone. The trailing "." on every vm_stat count
  # splits off an empty final field, which is what makes NF-1 the count on
  # every line regardless of how many words the label has.
  free="$(printf '%s\n' "$out" | awk -F'[ :.]+' '/^Pages free/ {print $(NF - 1)}')"
  inactive="$(printf '%s\n' "$out" | awk -F'[ :.]+' '/^Pages inactive/ {print $(NF - 1)}')"
  speculative="$(printf '%s\n' "$out" | awk -F'[ :.]+' '/^Pages speculative/ {print $(NF - 1)}')"
  wired="$(printf '%s\n' "$out" | awk -F'[ :.]+' '/^Pages wired down/ {print $(NF - 1)}')"
  # Field-by-field, not concatenated: a concatenated check can pass with one
  # field silently empty as long as the others are still all-digits.
  for v in "$page_size" "$free" "$inactive" "$speculative" "$wired"; do
    case "$v" in
      '' | *[!0-9]*) return 1 ;;
    esac
  done
  printf '%s %s\n' \
    $(((free + inactive + speculative) * page_size / 1048576)) \
    $((wired * page_size / 1048576))
}

# Precondition wrapper over mem_stat_mb. $1 = required shard size in MB.
# 0/unset disables the rung cleanly — no vm_stat read at all, same "0 = off"
# convention as CLUSTER_WARM_RECHECK_SECS.
# Sets MEM_HEADROOM_DETAIL on refusal (and on an unreadable probe), for the
# caller's log line.
mem_headroom_ok() {
  local required="$1" stat_out free wired
  case "$required" in
    '' | *[!0-9]*) return 0 ;;
  esac
  [ "$required" -gt 0 ] || return 0
  if ! stat_out="$(mem_stat_mb)"; then
    MEM_HEADROOM_DETAIL="could not read vm_stat; refusing to guess whether the shard fits"
    return 1
  fi
  read -r free wired <<< "$stat_out"
  [ "$free" -ge "$required" ] && return 0
  MEM_HEADROOM_DETAIL="${free}MB free (+reclaimable) against ${required}MB required for the shard"
  if [ "$wired" -ge "$required" ]; then
    # J1's no-rank-alive gate has already proved no rank process survives — so
    # wired this high with nothing left
    # to hold it is the unreclaimed-Metal signature from a prior crashed rank,
    # not a live session. Log-only: this never gates the verdict, it only
    # tells the operator a reboot is the remedy.
    MEM_HEADROOM_DETAIL="$MEM_HEADROOM_DETAIL (${wired}MB is wired with no surviving rank process — the unreclaimed-Metal signature; only a reboot returns it)"
  fi
  return 1
}

# J5 runs this after J1 proved no rank survives and J4 quiesced the host's
# standalone serving. Measuring before those steps would count memory that the
# join is about to free, and could refuse a shard that fits once serving stops.
#
# This gate runs before J6 arms either peer and before J9 can launch a rank, so a
# refusal consumes no protection domain. MEM_HEADROOM_DETAIL is returned for
# the lifecycle log.
#
# TWO QUESTIONS, NOT ONE. mem_headroom_ok asks "is there enough FREE memory for
# the shard's ordinary resident pages". wired_ceiling_room_ok below asks the
# question free memory cannot answer at all: "does the shard's WIRED demand
# still fit under the GPU wired ceiling, with the compositor's own draw left
# standing". Both must hold; either alone is a false green.
rank_start_room_ok() {
  local required="${CLUSTER_SHARD_MEMORY_MB:-}"
  if ! [[ "$required" =~ ^[0-9]{1,8}$ ]] || [ "$((10#${required:-0}))" -le 0 ]; then
    MEM_HEADROOM_DETAIL="room-unconfigured: CLUSTER_SHARD_MEMORY_MB must be a positive integer"
    return 1
  fi
  mem_headroom_ok "$required" && wired_ceiling_room_ok "$required"
}

# THE RUNG THAT REFUSES A START ONTO AN ALREADY-POISONED HOST.
#
# THE FAILURE MODE. A worker killed by an uncaught exception during a Metal
# teardown strands its wired GPU allocations: the pages stay wired with no
# owning process, and only a reboot returns them. A rank that then starts onto
# that host adds its own shard on top, and the compositor — which draws from
# the same wired pool — can be starved of command buffers near the ceiling,
# taking the host down with it.
#
# WHY THE FREE-MEMORY RUNG ABOVE DOES NOT CATCH IT. Stranded wired pages are
# not free, so on a 128 GiB host tens of GiB can be unreclaimable while
# free+reclaimable still comfortably covers a ~50 GiB shard: mem_headroom_ok
# passes, correctly. Free memory and the wired ceiling are different budgets.
#
# WHY NOT A STATIC WIRED CEILING INSTEAD. Because usage is DESIGNED to run up
# toward the ceiling — a healthy serving rank wires approximately its whole
# shard (measured: ~9 GiB of MLX-attributable wired against 7.6 GiB of
# resident standalone model weights). No absolute wired
# threshold below the ceiling separates legitimate load from a leak, which is
# why nix-darwin's separate runtime wired-ceiling automation is left disabled.
# This rung is not a threshold on wired: it is arithmetic on the HEADROOM
# REMAINING once this specific shard is added.
#
# WHY THE NAIVE FORM IS A FALSE GREEN. `wired + shard <= ceiling` permits a
# start that starves the compositor: 47104 MB already wired + a 51200 MB shard
# is 98304 MB, under a 102400 MB ceiling, and compositor starvation is reached
# below that sum. The ceiling is the wrong comparison point
# because the compositor draws from the same wired pool and the ceiling
# reserves it nothing (osReserveGb reserves ordinary RAM, not GPU-wired
# pages). So the budget is the ceiling MINUS a compositor reserve.
#
# FAILS CLOSED. An unreadable probe refuses the start because no rank is
# running yet and refusing costs no protection domain. A later join repeats the
# same gate after the source of the unreadable result is fixed.
#
# This check is scoped to the room available at J5. It does not monitor wired
# memory during a formed session; detach verifies the rank and measured PD count
# during teardown.
#
# $1 = required shard size in MB; 0/unset disables the rung with no probe at
# all, and CLUSTER_COMPOSITOR_RESERVE_MB=0 disables it independently.
# MEM_HEADROOM_DETAIL carries refusal detail to cluster-join's lifecycle log.
wired_ceiling_room_ok() {
  local required="$1" reserve ceiling stat_out free wired budget
  case "$required" in
    '' | *[!0-9]*) return 0 ;;
  esac
  [ "$required" -gt 0 ] || return 0
  reserve="${CLUSTER_COMPOSITOR_RESERVE_MB:-0}"
  case "$reserve" in
    '' | *[!0-9]*) reserve=0 ;;
  esac
  [ "$reserve" -gt 0 ] || return 0
  # GROUND TRUTH, NOT THE CONFIGURED VALUE. CLUSTER_WIRED_LIMIT_MB is what the
  # module MEANT to apply; rung 3 (set_wired_limit) is what actually applied
  # it, and a missing sudoers grant is exactly how a guard in this subsystem
  # has silently gone inert before. Absolute path for the same reason
  # current_boot_epoch uses one — a sysctl off a sanitized PATH already
  # disabled the halt marker once. CLUSTER_SYSCTL_BIN is a test seam, like
  # CLUSTER_VMSTAT_BIN.
  ceiling="$("${CLUSTER_SYSCTL_BIN:-/usr/sbin/sysctl}" -n iogpu.wired_limit_mb 2> /dev/null)" || ceiling=""
  case "$ceiling" in
    '' | *[!0-9]* | 0)
      # 0 means "no explicit ceiling" (the kernel picks its own), which at THIS
      # call site also means rung 3 failed to apply the cluster ceiling. Either
      # way the arithmetic below has no defensible operand, so refuse.
      MEM_HEADROOM_DETAIL="could not read a usable iogpu.wired_limit_mb (got '${ceiling}'); refusing to guess whether the shard fits under the GPU wired ceiling"
      return 1
      ;;
  esac
  if ! stat_out="$(mem_stat_mb)"; then
    MEM_HEADROOM_DETAIL="could not read vm_stat; refusing to guess how much wired memory this host already holds"
    return 1
  fi
  read -r free wired <<< "$stat_out"
  budget=$((ceiling - reserve))
  if [ "$budget" -le 0 ]; then
    MEM_HEADROOM_DETAIL="compositor reserve ${reserve}MB is at or above the ${ceiling}MB wired ceiling; refusing rather than starting under a ${budget}MB budget"
    return 1
  fi
  [ $((wired + required)) -le "$budget" ] && return 0
  MEM_HEADROOM_DETAIL="${wired}MB already wired + ${required}MB the shard will wire exceeds the ${budget}MB start budget (${ceiling}MB iogpu.wired_limit_mb less ${reserve}MB held back for the compositor)"
  # WHICH BLOCKER IS IT — and do NOT guess. There are exactly two ways to be
  # over budget, and they need opposite remedies.
  if [ "$required" -gt "$budget" ]; then
    # The shard alone does not fit, on an empty host. That is configuration,
    # not a leak: no amount of reclaimed memory helps and a reboot changes
    # nothing. Naming reboot here would send an operator to restart a machine
    # that will refuse again identically.
    MEM_HEADROOM_DETAIL="$MEM_HEADROOM_DETAIL. The ${required}MB shard alone exceeds the ${budget}MB budget, so this refuses on an EMPTY host: a reboot will not change it. Raise iogpu.wired_limit_mb, lower compositorReserveMb, or correct shardMemoryMb"
  else
    # Wired is the blocker, and here that is unambiguous — unlike the same
    # signature in mem_headroom_ok, which runs pre-quiesce. J1's no-rank-alive
    # gate has proved no rank process survives, and standalone serving has
    # already been quiesced. So
    # nothing this host knows about is holding these pages: it is the
    # unreclaimed-Metal signature, and the operator must be told that killing
    # processes will not return it, because there are none left to kill.
    MEM_HEADROOM_DETAIL="$MEM_HEADROOM_DETAIL. The shard itself fits ($required <= $budget) — ${wired}MB of wired memory is the blocker, held with no rank process and standalone serving already quiesced. That is the unreclaimed-Metal leak signature: REBOOT is the only thing that returns it, there is no process to kill"
  fi
  return 1
}
