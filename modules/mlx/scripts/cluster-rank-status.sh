# shellcheck shell=bash
# Locating THE CLUSTER RANK PROCESS — the one process that owns an RDMA
# protection domain — and answering three-valued questions about it.
#
# Concatenated by the link watcher, cluster-join and cluster-detach. The SIGTERM
# reap built on these lives in ./cluster-rank-reap.sh, which only the two
# consumers that stop ranks are given.
#
# THE PATTERN IS NEVER A LITERAL HERE. It arrives as CLUSTER_RANK_PROCESS_PATTERN,
# single-defined in modules/mlx/cluster-rank-pattern.nix and derived from the
# same entry-point string that builds the rank argv. Five inline copies of
# '/mlx_lm\.server' used to live in cluster-join.sh and cluster-detach.sh; a
# pattern that stops matching is indistinguishable from "nothing to clean up",
# which is how a reap becomes a silent no-op and a survivor keeps its protection
# domain across a restart.
#
# Consumed environment:
#   CLUSTER_RANK_PROCESS_PATTERN   pgrep -f pattern for the rank engine
#   CLUSTER_PGREP_BIN              absolute pgrep (test seam; /usr/bin is not on
#                                a writeShellApplication PATH)

rank_process_pids() {
  "${CLUSTER_PGREP_BIN:-/usr/bin/pgrep}" -f "${CLUSTER_RANK_PROCESS_PATTERN:-}" 2> /dev/null
}

# THREE STATES, TWO PREDICATES, AND NEITHER IS THE OTHER'S NEGATION.
#
# pgrep exits 0 for "matched", 1 for "did not match", and 2/3 (127 when the
# binary is absent) for "I could not answer". Collapsing those into one boolean
# is the entire bug class: a missing binary, an unset pattern and a sanitized
# PATH all read as "nothing is running" under `! pgrep …`, and "nothing is
# running" is the answer that lets a second rank start on top of the first.
#
# So an unanswerable probe makes BOTH predicates false, and each caller then
# fails closed in its own direction — a waiter keeps waiting instead of declaring
# success, a starter refuses to start instead of stacking a second rank, a
# teardown reports NOT-verified instead of safe-to-unplug.
rank_process_running() {
  local rc=0
  [ -n "${CLUSTER_RANK_PROCESS_PATTERN:-}" ] || return 1
  rank_process_pids > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ]
}

rank_process_absent() {
  local rc=0
  [ -n "${CLUSTER_RANK_PROCESS_PATTERN:-}" ] || return 1
  rank_process_pids > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ]
}
