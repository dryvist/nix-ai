# Memory-headroom precondition rung. Split into its own file rather than added
# to ./mlx-cluster-scripts.nix, which is already close to the 12KB error
# ceiling in .file-size.yml — same split-rather-than-exempt pattern as
# ./mlx-cluster-pd-callsites.nix.
{
  pkgs,
  src,
}:
{
  # THE CHECK THAT FAILS IF A RANK CAN START INTO A SHARD THAT WILL NOT FIT.
  # Sources the shipped helpers + guards in the module's concatenation order,
  # exactly as tests/test-rank-start-guards.sh and tests/test-pd-debt.sh do,
  # and stubs only vm_stat (generated executable, not a shell function — see
  # the test header for why) plus the other macOS-only rungs. Asserts the
  # property that makes the 2026-08-01 chain impossible: a refusal here costs
  # no kickstart attempt and charges nothing to the PD ledger, real page-size
  # parsing (not a hardcoded 16384), and that a sustained refusal escalates to
  # a halt pd_auto_reboot_if_warranted actually recognizes.
  mlx-cluster-mem-headroom = pkgs.runCommand "check-mlx-cluster-mem-headroom" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.jq
    ];
    BOOT_SCOPE = "${src}/modules/mlx/scripts/cluster-boot-scope.sh";
    LEDGER = "${src}/modules/mlx/scripts/cluster-pd-ledger.sh";
    HELPERS = "${src}/modules/mlx/scripts/cluster-link-helpers.sh";
    GUARDS = "${src}/modules/mlx/scripts/cluster-link-guards.sh";
    CAUSE = "${src}/modules/mlx/scripts/cluster-pd-cause.sh";
    PEER_STATE = "${src}/modules/mlx/scripts/cluster-peer-state.sh";
  } "bash ${src}/tests/test-mem-headroom.sh && touch $out";
}
