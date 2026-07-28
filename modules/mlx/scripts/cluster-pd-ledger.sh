# shellcheck shell=bash
# RDMA protection-domain ledger — the READ side.
#
# Concatenated after ./cluster-boot-scope.sh by the link watcher, cluster-join
# and cluster-detach. The write side is ./cluster-pd-record.sh, which only the
# two consumers that can actually lose a domain are given.
#
# WHY A LEDGER EXISTS. A leaked protection domain is returned by nothing short of
# a reboot. The guard that already existed is REACTIVE: it counts consecutive
# failed rank starts and halts once errno 96 proves the domains are gone. Worse,
# its counter is SESSION-scoped — a link cycle, a settled rank or a cluster-join
# all reset it — so three domains could be leaked, the counter cleared, and three
# more leaked, without bound, inside a single boot. That is exactly how a machine
# reaches "reboot or nothing" while every guard reports green.
#
# The ledger is BOOT-scoped, and that is the whole mechanism: it counts only
# entries stamped with the current boot, so a reboot — the one event that
# actually returns a domain — is the one event that clears it. No separate expiry
# pass, no second marker scheme, and nothing a link cycle can reset.

# How many protection domains this boot has already lost. Prints an integer.
#
# Sums the domains= field rather than counting lines: one event can cost several
# domains (a PD-guard halt fires after N failed distributed inits, and every one
# of those N leaked), and a ledger that recorded that as "1" would under-count
# the resource it exists to protect.
#
# FAIL CLOSED IN BOTH DIRECTIONS. If this boot's epoch cannot be read, every
# entry counts. If an entry's boot field is missing, empty or 'unknown', that
# entry counts. If its domains field is missing or non-numeric, it counts as one.
# All three biases make a start MORE likely to be refused, never less — the
# opposite bias is precisely how the sysctl-off-PATH defect turned the halt
# marker into a no-op while still reporting that it was protecting the budget.
#
# Fields are read EXACTLY, not by a greedy regex: the detail text is
# operator-facing prose and must never be able to spoof a field this decision
# reads. awk is already a hard dependency of halt_drop_if_pre_boot, so this adds
# no new failure surface.
#
# $1 ledger file.
pd_debt_count() {
  local file="$1" boot
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    echo 0
    return 0
  fi
  boot="$(current_boot_epoch)"
  awk -F'\t' -v boot="${boot:-}" '
    {
      rec = ""; dom = ""; haveRec = 0; haveDom = 0
      # FIRST match wins, never the last. The detail text is the final field and
      # is operator-facing prose; a last-match loop let a detail beginning
      # "boot=0 domains=99 …" overwrite the real fields and drop its own entry
      # from the count — a self-erasing debt record. Caught by
      # tests/test-pd-debt.sh before it ever shipped, and the same first-match
      # rule halt_drop_if_pre_boot already uses.
      for (i = 1; i <= NF; i++) {
        if (!haveRec && $i ~ /^boot=/)    { rec = substr($i, 6); haveRec = 1 }
        if (!haveDom && $i ~ /^domains=/) { dom = substr($i, 9); haveDom = 1 }
      }
      if (boot != "" && rec != "" && rec != "unknown" && rec != boot) next
      n += (dom ~ /^[0-9]+$/) ? dom + 0 : 1
    }
    END { print n + 0 }
  ' "$file" 2> /dev/null
}

# The one operator-facing rendering of the debt, used by every consumer.
#
# ALWAYS A FRACTION OF THE DEVICE BUDGET, NEVER A BARE COUNT. "3 domains leaked"
# reads as a rounding error. "3 of 11 device protection domains consumed until
# reboot" is the actual severity: the pool is tiny — measured max_pd = 11 by
# ibv_devinfo -v on every RDMA device of this hardware, NOT the ~60 sessions
# ml-explore/mlx#3207 reports for other machines — and nothing short of a reboot
# returns one. The phrasing is defined once here so a message cannot drift back
# to a bare count in one place while the others stayed honest.
#
# The guard cap rides alongside as a SEPARATE fact, because the two answer
# different questions: the fraction says how much of the device is already gone,
# the cap says when this host stops spending. The cap sits well under the budget
# on purpose — it reserves domains for a session that actually works, rather than
# marking the distance to exhaustion.
#
# The budget renders as "?" when unset rather than defaulting to a number: an
# invented denominator is worse than a visibly missing one.
#
# $1 domains consumed this boot, $2 the guard cap.
pd_debt_phrase() {
  echo "$1 of ${CLUSTER_PD_DEVICE_BUDGET:-?} device protection domains consumed until reboot (guard cap $2)"
}
