# shellcheck shell=bash
# RULE 2 — generation parity is a hard gate, and the gate needs an automatic
# key. Detection went on the watcher's clock in the 86-hour fix; the HEAL still
# lived only in cluster-join, which a human has to run — so an unattended
# machine could know it was drifted, page about it, and stay drifted forever.
#
# The constraint that kept the heal out of the watcher is real and stays
# honoured: a `darwin-rebuild switch` fired FROM a launchd agent is SIGKILLed
# mid-activation by the very activation it runs (home-manager boots agents out
# to reload them), and a half-applied activation is worse than drift. So the
# watcher never runs the rebuild itself. It SUBMITS a transient launchd job
# under its own label (CLUSTER_GENERATION_HEAL_LABEL) — owned by launchd
# directly, not by the watcher's process tree, and not a label home-manager
# manages — so booting the watcher out mid-activation cannot kill the rebuild.
# The job's command always exits 0 (`|| true`), because launchctl submit
# restarts a job that exits nonzero and a failing rebuild must not become an
# unbounded retry loop; success is judged the only honest way — by re-reading
# parity after the job finishes.
# ponytail: launchctl submit is deprecated but present through macOS 26; if it
# is ever removed, replace with a generated plist + `launchctl bootstrap` under
# the same label.
#
# Function definitions ONLY, concatenated into the link watcher (the single
# consumer). Reads the watcher-scope vars `uid` and `gen_parity_file` at call
# time, the same contract as every other watcher helper.
#
# Consumed environment:
#   CLUSTER_GENERATION_REPO        deploy source of truth (owner/repo)
#   CLUSTER_GENERATION_HEAL_LABEL  launchd label of the transient heal job
#   CLUSTER_GENERATION_HEAL_MAX    rebuild attempts per distinct deploy rev
#   CLUSTER_LAUNCHCTL_BIN          launchctl path (test seam)

# $1 = the parity fact the watcher already read this tick, $2 = attempts ledger
# (`<rev> <count>[ paged]`). Bounded: per distinct deploy revision, at most
# CLUSTER_GENERATION_HEAL_MAX submissions and exactly one page at the cap; a
# new deploy revision opens a fresh budget. Never touches a machine that is
# serving — the rebuild's activation reloads launchd agents, and tearing down a
# healthy rank to chase HEAD is churn the drift page already covers.
generation_heal_maybe() {
  local fact="$1" attempts_file="$2" rev lc max last_rev attempts flag heal_log
  case "$fact" in
    *'state=drift'*) ;;
    *) return 0 ;;
  esac
  rev="${fact##*deploy=}"
  [ -n "$rev" ] || return 0
  if rank_process_running; then
    return 0
  fi
  lc="${CLUSTER_LAUNCHCTL_BIN:-launchctl}"
  if "$lc" print "gui/$uid/${CLUSTER_GENERATION_HEAL_LABEL:?}" > /dev/null 2>&1; then
    if "$lc" print "gui/$uid/$CLUSTER_GENERATION_HEAL_LABEL" 2> /dev/null | grep -q "state = running"; then
      return 0 # heal in flight; the one thing that must not happen is a second one
    fi
    # The previous heal finished. Drop the job so a resubmission is possible,
    # and drop the parity CACHE so the next tick re-reads the truth instead of
    # serving a pre-heal "drift" verdict for the rest of the TTL.
    "$lc" remove "$CLUSTER_GENERATION_HEAL_LABEL" 2> /dev/null || true
    rm -f "${gen_parity_file:-}"
    return 0
  fi
  max="${CLUSTER_GENERATION_HEAL_MAX:-2}"
  last_rev="" attempts=0 flag=""
  if [ -f "$attempts_file" ]; then
    read -r last_rev attempts flag < "$attempts_file" || true
  fi
  case "$attempts" in
    '' | *[!0-9]*) attempts=0 ;;
  esac
  [ "$last_rev" = "$rev" ] || attempts=0
  if [ "$attempts" -ge "$max" ]; then
    if [ "$flag" != "paged" ] || [ "$last_rev" != "$rev" ]; then
      printf '%s %s paged\n' "$rev" "$attempts" > "$attempts_file"
      alert "$(hostname -s): generation drift persists after $attempts detached rebuild attempt(s) toward deploy ${rev:0:12} — the automatic heal has stopped. Rank starts stay refused (hard gate) until parity is restored; run cluster-join here, or read $(dirname "${CLUSTER_STATE_FILE:-/dev/null}")/generation-heal.log for the rebuild output." \
        "mlx-cluster generation heal exhausted"
    fi
    return 1
  fi
  printf '%s %s\n' "$rev" "$((attempts + 1))" > "$attempts_file"
  heal_log="$(dirname "${CLUSTER_STATE_FILE:-/dev/null}")/generation-heal.log"
  echo "cluster-link: GENERATION HEAL — submitting a detached rebuild to deploy ${rev:0:12} (attempt $((attempts + 1))/$max, label $CLUSTER_GENERATION_HEAL_LABEL, log $heal_log)"
  "$lc" submit -l "$CLUSTER_GENERATION_HEAL_LABEL" -o "$heal_log" -e "$heal_log" -- \
    /bin/sh -c "sudo -n /run/current-system/sw/bin/darwin-rebuild switch --flake 'github:$CLUSTER_GENERATION_REPO/$rev' || true" ||
    {
      echo "cluster-link: WARN launchctl submit failed for $CLUSTER_GENERATION_HEAL_LABEL; the heal did not start" >&2
      return 1
    }
}
