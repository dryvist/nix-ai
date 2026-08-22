# shellcheck shell=bash
# RDMA protection-domain ledger — the CROSS-BOOT, CAUSE-KEYED side.
#
# Concatenated after ./cluster-pd-ledger.sh and given ONLY to the link watcher,
# the one consumer that decides whether to spend another domain. cluster-join
# refuses at the boot-scoped cap and cluster-detach only records; neither reads a
# cross-boot total, and a function shipped to a script that cannot call it is an
# SC2329 build failure (see ../cluster-script-layers.nix).
#
# WHY A SECOND ACCOUNTING AXIS. pd_debt_count is BOOT-scoped by design: a reboot
# returns every leaked domain, so a reboot must clear the ledger. That is correct
# and it is also the escape hatch a repeating defect uses. A cause that leaks
# domains, reboots, and leaks them again is invisible to a boot-scoped counter —
# every boot starts from an empty budget and every boot spends it the same way,
# which is precisely the shape of an unattended loop nobody is watching. The
# 2026-08-07 and 2026-08-08 nights were two instances of it.
#
# So debt is also totalled ACROSS ALL BOOTS, keyed by the halt cause it was
# spent on. The boot-scoped cap says "stop spending until a reboot"; this says
# "stop spending on THIS reason, permanently, until an operator says otherwise".
#
# THE RESET IS EVIDENCE-GATED, NOT AUTOMATIC. A reboot must not clear it — the
# whole point is to survive one — and neither may a link cycle, a manual marker
# delete, or cluster-join. Exactly two things clear a bucket, and both are a
# statement that the cause is no longer live:
#
#   source=cause-budget-reset  an operator appended it by hand, having looked.
#   source=soak-settle         this host completed a formation, passed the
#                              health gate, and then passed a periodic soak
#                              probe against the running pipeline. That chain
#                              is only reachable once the cluster demonstrably
#                              works, which is the same thing the operator was
#                              being asked to confirm.
#
# Anything cheaper reproduces the loop this closes: a link cycle proves nothing,
# a marker delete proves nothing, and a reboot proves nothing precisely because
# the failure being counted survives one. A served request does.
#
# Consumed environment:
#   CLUSTER_PD_DEBT_FILE      the ledger (single definition, from the module)
#   CLUSTER_PD_CAUSE_BUDGET   domains one cause may spend across all boots;
#                             0/unset disables the axis entirely

# Domains spent on ONE cause across every boot in the ledger. Prints an integer.
#
# Differs from pd_debt_count in exactly two ways, and both are the point: no boot
# filter, and a cause filter. Everything else — sum domains= rather than count
# lines, first-match-wins field extraction, a non-numeric domains= counting as
# one — is deliberately identical, because two ledger readers that parse the same
# file by different rules is how a writer and a reader end up disagreeing about
# what is written down.
#
# BACKWARD COMPATIBILITY IS A BUCKET, NOT A SPECIAL CASE. Entries written before
# this field existed carry no cause=, so they land in the empty-string bucket. No
# halt cause is the empty string, so that bucket is never queried and never
# blocks anything. Old ledgers keep counting against the boot-scoped cap exactly
# as they did, and nothing has to be migrated.
#
# A reset entry zeroes the running total rather than being subtracted from it, so
# only what was spent AFTER the operator looked counts. A reset carrying no
# cause= resets every bucket; one carrying cause=<x> resets only that bucket.
#
# $1 ledger file, $2 cause token.
pd_cause_total() {
  local file="$1" want="$2"
  if [ -z "$file" ] || [ ! -f "$file" ] || [ -z "$want" ]; then
    echo 0
    return 0
  fi
  awk -F'\t' -v want="$want" '
    {
      cause = ""; dom = ""; src = ""
      haveCause = 0; haveDom = 0; haveSrc = 0
      # FIRST match wins, exactly as pd_debt_count does, and for the same
      # reason: the final field is operator-facing prose, and a detail beginning
      # "cause=peer-absent domains=99" must not be able to spoof the fields this
      # decision reads.
      for (i = 1; i <= NF; i++) {
        if (!haveCause && $i ~ /^cause=/)   { cause = substr($i, 7); haveCause = 1 }
        if (!haveDom   && $i ~ /^domains=/) { dom   = substr($i, 9); haveDom = 1 }
        if (!haveSrc   && $i ~ /^source=/)  { src   = substr($i, 8); haveSrc = 1 }
      }
      if ((src == "cause-budget-reset" || src == "soak-settle") && (cause == "" || cause == want)) { n = 0; next }
      if (cause != want) next
      n += (dom ~ /^[0-9]+$/) ? dom + 0 : 1
    }
    END { print n + 0 }
  ' "$file" 2> /dev/null
}

# The cause this host would spend its next domain on, or empty when it has never
# halted. Prints a bare token.
#
# THE LATCH FIRST, THEN ITS CROSS-BOOT SIBLING. The latch is cleared by every
# reboot (halt_drop_if_pre_boot), so keying only on it leaves a reader inert
# until the first halt of each new boot. halt_cause_file
# (./cluster-link-helpers.sh) survives that reset and answers the same question
# one boot later. Latch first because it is the CURRENT verdict; the sibling is
# only consulted when there is no current one.
#
# Shared by the two readers below rather than written twice: the budget rung and
# the settle both have to name the SAME bucket, and two copies of this
# resolution order is how one of them ends up crediting a bucket the other is
# still billing.
#
# $1 halt latch file.
pd_cause_would_be() {
  local latch_file="$1" cause
  [ -n "$latch_file" ] || return 0
  cause="$(cat "$latch_file" 2> /dev/null || echo '')"
  [ -n "$cause" ] || cause="$(cat "$(halt_cause_file "$latch_file")" 2> /dev/null || echo '')"
  # The latch holds one bare token; trim anything that follows so a future
  # multi-word latch cannot silently stop matching a ledger bucket.
  printf '%s' "${cause%%[[:space:]]*}"
}

# Settle the cause budget against a WORKING cluster.
#
# Called from the watcher's soak-probe PASS branch and from nowhere else. By the
# time that branch runs, this host has formed the cluster, passed the full
# health gate, and then answered a real completion against the running pipeline
# — the evidence chain the header above names. A cause cannot simultaneously be
# the reason this host cannot cluster and be true of a host that is clustered
# and serving, so its running total is retired.
#
# APPENDS, NEVER REWRITES. The ledger is an audit trail; the history lines that
# recorded the spend stay exactly where they are and pd_debt_count still sums
# them against the boot-scoped cap. Only pd_cause_total's cross-boot view is
# zeroed, and only for this one bucket. domains=0 so the entry itself bills
# nothing.
#
# SILENT WHEN THERE IS NOTHING TO SETTLE — no would-be cause, or a bucket
# already at zero. The soak probe passes every recheck interval for the life of
# a healthy session, and an entry per pass would bury the ledger it is written
# into. A settle that actually retires a total logs what it retired.
#
# $1 halt latch file.
pd_cause_settle_on_evidence() {
  local latch_file="$1" cause total
  cause="$(pd_cause_would_be "$latch_file")"
  [ -n "$cause" ] || return 0
  total="$(pd_cause_total "${CLUSTER_PD_DEBT_FILE:-}" "$cause")"
  case "$total" in
    '' | *[!0-9]*) total=0 ;;
  esac
  [ "$total" -gt 0 ] || return 0
  pd_debt_record "${CLUSTER_PD_DEBT_FILE:-}" 0 soak-settle \
    "soak probe passed on a formed, health-gated cluster; retiring $total domain(s) billed to this cause" \
    "$cause"
  echo "cluster-link: soak PASS settles the cross-boot cause budget for '$cause' ($total domain(s) retired) — a host that is clustered and serving is not the host that could not cluster. History lines are kept; only the running total is cleared."
}

# Is the cause this host keeps halting on still allowed to spend a domain?
#
# THE LATCH IS THE "WOULD-BE CAUSE". A precondition rung runs before anything has
# failed, so it cannot know what the next failure will be called — but it does
# know what the last one was called, because the halt latch survives a manual
# marker delete for exactly that purpose. A host that has halted on peer-absent
# and is about to retry is, on the evidence available, about to spend another
# domain on peer-absent. That is the bill this refuses to keep paying.
#
# The would-be cause is resolved by pd_cause_would_be above, latch first and its
# cross-boot sibling second. Keyed on the latch alone this rung would be inert
# until the first halt of each new boot, and a cause already at budget would
# then bill a fresh couple of domains every boot, forever. Neither file present
# means this host has never halted, so there is no would-be cause and nothing to
# refuse.
#
# IT LOGS ITS OWN REFUSAL rather than handing the text back through a variable
# for the caller to print, which is what the neighbouring mem_headroom_ok does
# with MEM_HEADROOM_DETAIL. That idiom works there because the rung and its
# caller share a file; here they do not, and a variable set in one layer and
# read in another is invisible to shellcheck — it reads as dead and the
# contract is enforced by nothing. Two lines on a refusal is the cost, and they
# divide honestly: this one states the ledger fact, the caller states what it
# decided to do about it.
#
# $1 halt latch file. 0 = the cause may still spend.
pd_cause_budget_ok() {
  local latch_file="$1" budget cause total
  budget="${CLUSTER_PD_CAUSE_BUDGET:-0}"
  case "$budget" in
    '' | *[!0-9]*) return 0 ;;
  esac
  [ "$budget" -gt 0 ] || return 0
  [ -n "$latch_file" ] || return 0
  cause="$(pd_cause_would_be "$latch_file")"
  [ -n "$cause" ] || return 0
  total="$(pd_cause_total "${CLUSTER_PD_DEBT_FILE:-}" "$cause")"
  case "$total" in
    '' | *[!0-9]*) total=0 ;;
  esac
  [ "$total" -lt "$budget" ] && return 0
  echo "cluster: halt cause '$cause' has cost $total protection domain(s) across ALL boots (cross-boot budget $budget). A reboot does NOT clear this and neither does a link cycle or a marker delete. Two things do: this host completing a formation, health gate and soak probe (which settles it automatically, because a cluster that serves is the evidence being asked for), or an entry appended with source=cause-budget-reset once the underlying defect is understood. Reaching this budget means the peer-armed handshake is not doing its job, because a start against a peer that cannot rendezvous is supposed to cost nothing." >&2
  return 1
}
