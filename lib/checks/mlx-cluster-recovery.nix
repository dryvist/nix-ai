# Cluster teardown/bring-up recovery checks — the 2026-08-08 family.
#
# Split into its own file rather than added to ./mlx-cluster-selfheal.nix, which
# was already near the 6KB warn threshold in .file-size.yml (split rather than
# grow, the same pattern as modules/mlx/options).
#
# ONE SHAPE, THREE PLACES. A component takes something away — standalone
# serving, a running rank, a start attempt — and the path that was supposed to
# give it back either does not exist or is never reached:
#
#   * cluster-join quiesced serving, failed to form a cluster, and exited; with
#     no halt recorded, nothing on the host restored anything (20+ minutes
#     serving nothing);
#   * cluster-detach signalled the rank process while the watcher, never told a
#     detach was under way, kickstarted ranks into the middle of the teardown
#     (three protection domains);
#   * a nominal watcher tick logged nothing at all, so a live watcher and one
#     that had stopped being scheduled were indistinguishable.
{
  pkgs,
  src,
}:
{
  # THE CHECK THAT FAILS IF A LIFECYCLE COMMAND CAN LEAVE THE HOST WORSE THAN IT
  # FOUND IT (2026-08-08). cluster-join must give standalone serving back on
  # every exit after its quiesce that is not a formed cluster, and cluster-detach
  # must unload the rank JOB before it signals the process — otherwise the
  # watcher, which is never told a detach is under way, kickstarts ranks into the
  # middle of the teardown — and must both bootstrap that job back and settle the
  # session's kickstart budget on the way out.
  mlx-cluster-teardown-recovery = pkgs.runCommand "check-mlx-cluster-teardown-recovery" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
    ];
    BOOT_SCOPE = "${src}/modules/mlx/scripts/cluster-boot-scope.sh";
    LEDGER = "${src}/modules/mlx/scripts/cluster-pd-ledger.sh";
    RECORD = "${src}/modules/mlx/scripts/cluster-pd-record.sh";
    STAGE = "${src}/modules/mlx/scripts/cluster-pd-stage.sh";
    SETTLE = "${src}/modules/mlx/scripts/cluster-pd-settle.sh";
    STATUS = "${src}/modules/mlx/scripts/cluster-rank-status.sh";
    RESTORE = "${src}/modules/mlx/scripts/cluster-serving-restore.sh";
    JOIN = "${src}/modules/mlx/scripts/cluster-join.sh";
    DETACH = "${src}/modules/mlx/scripts/cluster-detach.sh";
    LAYERS = "${src}/modules/mlx/cluster-script-layers.nix";
  } "bash ${src}/tests/test-teardown-recovery.sh && touch $out";

  # THE CHECK THAT FAILS IF A LIVE WATCHER AND A DEAD ONE LOG THE SAME THING. A
  # nominal tick decides nothing and so used to write nothing, making a healthy
  # watcher indistinguishable from one that had stopped being scheduled. Also
  # pins that a kickstart which launched nothing consumes no start attempt —
  # cluster-detach leaves the rank job unloaded for the length of a teardown, and
  # counting those failures would manufacture protection-domain debt.
  mlx-cluster-watcher-heartbeat = pkgs.runCommand "check-mlx-cluster-watcher-heartbeat" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
      pkgs.gnused
    ];
    STATUS = "${src}/modules/mlx/scripts/cluster-rank-status.sh";
    WATCHER = "${src}/modules/mlx/scripts/cluster-link-watcher.sh";
  } "bash ${src}/tests/test-watcher-heartbeat.sh && touch $out";

  # THE CHECK THAT FAILS IF A REFUSAL AFTER QUIESCE LEAVES SERVING DOWN.
  # quiesce_normal_serving kills in-flight Hermes requests outright (no drain);
  # a room-check refusal or a launchctl kickstart failure downstream of it used
  # to just return, leaving standalone serving down for an attempt that never
  # started a rank. Pins that both refusal paths restore it, and that a
  # successful kickstart does not (the rank is what serves next).
  mlx-cluster-quiesce-restore = pkgs.runCommand "check-mlx-cluster-quiesce-restore" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
    ];
    WATCHER = "${src}/modules/mlx/scripts/cluster-link-watcher.sh";
  } "bash ${src}/tests/test-quiesce-restore.sh && touch $out";

  # THE CHECK THAT FAILS IF A BUSY-BUT-HEALTHY RANK GETS DECLARED WEDGED.
  # The soak probe used to trust only endpoint_busy (a held TCP connection) as
  # proof the pipeline was busy rather than dead — which misses a client that
  # disconnected on its own timeout while the backend was still occupied. Pins
  # that real generation progress (new_progress_lines) is checked first and
  # short-circuits the probe.
  mlx-cluster-soak-busy-vs-wedged = pkgs.runCommand "check-mlx-cluster-soak-busy-vs-wedged" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
    ];
    WATCHER = "${src}/modules/mlx/scripts/cluster-link-watcher.sh";
  } "bash ${src}/tests/test-soak-busy-vs-wedged.sh && touch $out";

  # THE CHECK THAT FAILS IF A WORKER KEEPS RUNNING INSIDE AN ABANDONED GROUP.
  # Readiness, the health gate and the soak are all coordinator-gated, so a
  # worker whose coordinator halts while its own rank survives had no teardown
  # of its own. Pins that the worker strikes only on a positive halted_cause in
  # the peer's published state, never on an unreadable fetch, and runs the same
  # halt-first SIGTERM standdown at the cap.
  mlx-cluster-peer-halt-standdown = pkgs.runCommand "check-mlx-cluster-peer-halt-standdown" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
      pkgs.jq
    ];
    WATCHER = "${src}/modules/mlx/scripts/cluster-link-watcher.sh";
  } "bash ${src}/tests/test-peer-halt-standdown.sh && touch $out";

}
