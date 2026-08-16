# Counter-settle billing check, split out of ./mlx-cluster-scripts.nix at the
# 12KB file cap in .file-size.yml — same split-rather-than-exempt pattern as
# ./mlx-cluster-halt-boot-scope's own split, and ./mlx-cluster-recovery.nix's.
#
# Duplicates the handful of guard-layer script paths this one check needs
# rather than importing mlx-cluster-scripts.nix's `guardLayers`: that binding
# is local to its own file, and reaching across for seven short strings would
# cost more than repeating them — the same call ./mlx-cluster-recovery.nix and
# ./mlx-cluster-peer-armed.nix already made.
{
  pkgs,
  src,
}:
{
  # THE CHECK THAT FAILS IF A COUNTER RESET CAN DISCARD LEAKED DOMAINS, OR CAN
  # BILL DOMAINS THAT WERE NEVER SPENT. mlx-cluster-pd-debt covers the ledger
  # at the CAP; this covers the hole underneath: the kickstart counter is
  # session-scoped and five paths reset it (a link cycle, a settled rank,
  # cluster-join, cluster-detach, an accepted manual clear), but the ledger
  # was only written at the cap, so a counter at 1 or 2 reset elsewhere left
  # no trace of the domains those attempts leaked. Asserts the transfer
  # arithmetic (including the fail-closed direction, where an unguarded
  # subtraction would compute a NEGATIVE debt and record nothing), that the
  # transfer is errno-aware (a run whose every outstanding attempt is provably
  # jaccl Stage-A-only bills nothing — it could not have allocated a
  # protection domain — while Stage-B or unclassifiable evidence still bills
  # in full), and pins the call sites as source.
  mlx-cluster-pd-counter-settle = pkgs.runCommand "check-mlx-cluster-pd-counter-settle" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
    ];
    BOOT_SCOPE = "${src}/modules/mlx/scripts/cluster-boot-scope.sh";
    LEDGER = "${src}/modules/mlx/scripts/cluster-pd-ledger.sh";
    RECORD = "${src}/modules/mlx/scripts/cluster-pd-record.sh";
    # jaccl Stage-A/Stage-B classifier — see cluster-pd-stage.sh. A settle
    # window that never reached Stage B (ibv_alloc_pd) bills nothing.
    STAGE = "${src}/modules/mlx/scripts/cluster-pd-stage.sh";
    SETTLE = "${src}/modules/mlx/scripts/cluster-pd-settle.sh";
    WATCHER = "${src}/modules/mlx/scripts/cluster-link-watcher.sh";
    JOIN = "${src}/modules/mlx/scripts/cluster-join.sh";
    DETACH = "${src}/modules/mlx/scripts/cluster-detach.sh";
  } "bash ${src}/tests/test-pd-counter-settle.sh && touch $out";
}
