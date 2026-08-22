# shellcheck shell=bash
# RULE 2 — generation parity is a hard gate. Detection runs on the watcher's
# clock so an unattended machine finds drift without anyone running a command;
# this file turns that detection into a page.
#
# It does NOT rebuild the machine, and nothing here may. Parity is judged
# against one repo's origin/main, so a host deployed from any other flake — a
# private wrapper extending this one, for instance — reports drift on every
# tick, forever. An automatic rebuild there heals nothing: it replaces that
# host's correct configuration with a different repo's, on a timer, silently
# undoing every deploy. Deploying a host is a deliberate `darwin-rebuild
# switch` run by whoever owns that host's flake.
#
# The gate still holds without the rebuild: rank starts stay refused while
# parity is broken, and the page names the host and the deploy revision. What
# is given up is unattended self-repair, which was never sound — a repair has
# to know what to repair INTO, and this had no way to know.
#
# Function definitions ONLY, concatenated into the link watcher (the single
# consumer). Reads the watcher-scope var `gen_parity_file` at call time, the
# same contract as every other watcher helper.

# $1 = the parity fact the watcher already read this tick, $2 = the paged
# ledger (`<rev> paged`). At most one page per distinct deploy revision, so a
# host that stays drifted does not page every tick; a new deploy revision
# opens a fresh page. Never pages a machine that is serving — pulling
# attention off a healthy rank to chase HEAD is churn.
#
# BOTH REFUSING STATES PAGE. state=unstamped is as hard a gate as state=drift
# (rank_start_preconditions_ok refuses on either), but only drift used to page —
# so a host whose running generation carries no configurationRevision sat
# refusing every start silently, forever. The remedy differs enough to be worth
# naming: drift means deploy this host again, unstamped means the running
# generation was built from a dirty or local checkout and there is no revision
# to compare at all, so it has to be deployed from the committed flake ref.
generation_heal_maybe() {
  local fact="$1" attempts_file="$2" rev last_rev flag state
  case "$fact" in
    *'state=drift'*) state=drift ;;
    *'state=unstamped'*) state=unstamped ;;
    *) return 0 ;;
  esac
  rev="${fact##*deploy=}"
  [ -n "$rev" ] || return 0
  if rank_process_running; then
    return 0
  fi
  last_rev="" flag=""
  if [ -f "$attempts_file" ]; then
    read -r last_rev flag < "$attempts_file" || true
  fi
  if [ "$last_rev" = "$rev" ] && [ "$flag" = "paged" ]; then
    return 1
  fi
  printf '%s paged\n' "$rev" > "$attempts_file"
  if [ "$state" = unstamped ]; then
    alert "$(hostname -s): running system generation carries no configurationRevision, so it cannot be compared against deploy ${rev:0:12} — it was built from a dirty or local checkout. Rank starts stay refused (hard gate) until this host is deployed from the committed flake ref." \
      "mlx-cluster generation unstamped"
  else
    alert "$(hostname -s): system generation does not match deploy ${rev:0:12}. Rank starts stay refused (hard gate) until parity is restored — deploy this host from the flake that manages it." \
      "mlx-cluster generation drift"
  fi
  return 1
}
