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
# TWO KEYS, NOT ONE. `source` names the MECHANISM that spent the domains (which
# code path recorded this) and `cause` names the REASON they were spent (which
# halt verdict this belongs to). They are usually the same word and `cause`
# defaults to `source` for exactly that reason — but they are not the same
# question, and the cross-boot budget in ./cluster-pd-cause.sh is keyed on the
# reason. A standdown recorded by one mechanism can be caused by peer-absence,
# and a budget that could only count mechanisms would split one recurring defect
# across every path that happened to record it.
#
# $1 ledger file, $2 domains lost (integer), $3 source token, $4 free-text
# detail, $5 cause token (optional; defaults to $3).
pd_debt_record() {
  local file="$1" domains="$2" source="$3" detail="$4" cause="${5:-$3}" boot
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
  cause="${cause//$'\t'/ }"
  cause="${cause//$'\n'/ }"
  boot="$(current_boot_epoch)"
  # cause= sits BEFORE the free-text detail, like every other field: the reader
  # takes the first match of each field name so that prose in the final field can
  # never spoof one.
  printf '%s\tboot=%s\tdomains=%s\tsource=%s\tcause=%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${boot:-unknown}" "$domains" "$source" "$cause" "$detail" \
    >> "$file" 2> /dev/null || true
}
