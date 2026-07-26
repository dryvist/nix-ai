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
