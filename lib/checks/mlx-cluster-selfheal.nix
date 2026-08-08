# Cluster self-heal, attribution and restore checks — the 2026-08-01 family.
#
# Split out of ./mlx-cluster-scripts.nix, which was already past 10KB against the
# 12KB error ceiling in .file-size.yml (split rather than exempt, the same
# pattern as modules/mlx/options).
#
# THE INCIDENT THESE PIN. The Thunderbolt link was down for 86 hours with the
# cable seated. Nothing was broken that anything was watching for:
#
#   * the node had drifted off the deployed system generation, so the activation
#     that aliases the link address never ran — and the only parity check in the
#     system lived in cluster-join, which a human has to start;
#   * the watcher probed the peer, failed, and never looked at its own link prep,
#     although it already carried the repair for exactly that condition;
#   * it logged one two-item GUESS 10,440 times, and the truth was neither item;
#   * cluster-detach on the worker reported "teardown verified" and exit 0 over a
#     host whose serving agents were all still booted out;
#   * cluster-join spent 600s and then surfaced jaccl's errno 60, which names
#     neither the cause nor the machine.
#
# Each check below fails if one of those becomes possible again. Every one
# sources the SHIPPED functions and additionally pins the call sites as source,
# because the defect in three of the five cases was a correct function that the
# path needing it never reached.
{
  pkgs,
  src,
}:
{
  # Watcher link self-heal + the facts line that replaced the guess, plus the
  # periodic generation-parity check and its once-per-drift page.
  mlx-cluster-link-self-heal = pkgs.runCommand "check-mlx-cluster-link-self-heal" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    FACTS = "${src}/modules/mlx/scripts/cluster-link-facts.sh";
    PARITY = "${src}/modules/mlx/scripts/cluster-generation-parity.sh";
    WATCHER = "${src}/modules/mlx/scripts/cluster-link-watcher.sh";
  } "bash ${src}/tests/test-link-self-heal.sh && touch $out";

  # The single restore definition, driven through both roles and every failure
  # mode — including a worker with no restore hook, which used to return 0 and is
  # the exact shape of the "teardown verified" report over a dead endpoint.
  mlx-cluster-serving-restore = pkgs.runCommand "check-mlx-cluster-serving-restore" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    RESTORE = "${src}/modules/mlx/scripts/cluster-serving-restore.sh";
    DETACH = "${src}/modules/mlx/scripts/cluster-detach.sh";
  } "bash ${src}/tests/test-serving-restore.sh && touch $out";

  # cluster-join's bounded peer preflight (fail fast, name the unprepared side)
  # and the now-shared generation-parity comparison it uses.
  mlx-cluster-join-preflight = pkgs.runCommand "check-mlx-cluster-join-preflight" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
    ];
    PROBE = "${src}/modules/mlx/scripts/cluster-peer-probe.sh";
    PREFLIGHT = "${src}/modules/mlx/scripts/cluster-join-preflight.sh";
    PARITY = "${src}/modules/mlx/scripts/cluster-generation-parity.sh";
    JOIN = "${src}/modules/mlx/scripts/cluster-join.sh";
  } "bash ${src}/tests/test-join-preflight.sh && touch $out";

  # RULE 1 — plugged in means clustered, no exceptions. Fails when a
  # detached-while-plugged machine can be a STABLE state again: the standalone
  # lease must self-expire (garbage = expired), admin-down ports must be
  # re-upped once no lease holds (bounded), the lease must gate the down path,
  # and detach/join must write/end the lease at their pinned call sites.
  mlx-cluster-plugged-means-clustered = pkgs.runCommand "check-mlx-cluster-plugged-means-clustered" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    FACTS = "${src}/modules/mlx/scripts/cluster-link-facts.sh";
    PARITY = "${src}/modules/mlx/scripts/cluster-generation-parity.sh";
    WATCHER = "${src}/modules/mlx/scripts/cluster-link-watcher.sh";
    DETACH = "${src}/modules/mlx/scripts/cluster-detach.sh";
    JOIN = "${src}/modules/mlx/scripts/cluster-join.sh";
  } "bash ${src}/tests/test-plugged-means-clustered.sh && touch $out";

  # RULE 2 — generation parity is a hard gate with an automatic key. Fails
  # when drift stops refusing rank starts (or a by-hand clear can bypass the
  # rung), and when the detached heal loses its bounds: single-flight, capped
  # per deploy rev, one page at the cap, never on a serving machine, success
  # judged by re-reading parity. Also pins the watcher's parity-first ordering
  # and the heal layer's presence in the shipped build.
  mlx-cluster-generation-gate = pkgs.runCommand "check-mlx-cluster-generation-gate" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
    ];
    BOOT_SCOPE = "${src}/modules/mlx/scripts/cluster-boot-scope.sh";
    LEDGER = "${src}/modules/mlx/scripts/cluster-pd-ledger.sh";
    HELPERS = "${src}/modules/mlx/scripts/cluster-link-helpers.sh";
    PARITY = "${src}/modules/mlx/scripts/cluster-generation-parity.sh";
    FACTS = "${src}/modules/mlx/scripts/cluster-link-facts.sh";
    STATUS = "${src}/modules/mlx/scripts/cluster-rank-status.sh";
    HEAL = "${src}/modules/mlx/scripts/cluster-generation-heal.sh";
    GUARDS = "${src}/modules/mlx/scripts/cluster-link-guards.sh";
    CAUSE = "${src}/modules/mlx/scripts/cluster-pd-cause.sh";
    PEER_STATE = "${src}/modules/mlx/scripts/cluster-peer-state.sh";
    WATCHER = "${src}/modules/mlx/scripts/cluster-link-watcher.sh";
    LAYERS = "${src}/modules/mlx/cluster-script-layers.nix";
  } "bash ${src}/tests/test-generation-heal.sh && touch $out";
}
