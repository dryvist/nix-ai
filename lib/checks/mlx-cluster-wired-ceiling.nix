# Runtime wired-ceiling guard. Split into its own file rather than added to
# ./mlx-cluster-scripts.nix, which is already close to the 12KB error ceiling
# in .file-size.yml — same split-rather-than-exempt pattern as
# ./mlx-cluster-mem-headroom.nix.
{
  pkgs,
  src,
}:
{
  # THE CHECK THAT FAILS WHEN A RUNNING RANK CAN STARVE THE COMPOSITOR.
  # Sources the shipped helpers + guards in the module's concatenation order,
  # exactly as ./mlx-cluster-mem-headroom.nix does, and stubs only vm_stat
  # (generated executable, not a shell function — see the test header). Asserts
  # the properties that make the 2026-08-01 hard reset impossible: a healthy
  # ~3.5 GiB-wired rank is never reaped, the 96.7 GiB incident shape is, real
  # page-size parsing decides the verdict, and an unreadable probe fails OPEN.
  # That last property is the inverse of mem_headroom_ok's fail-closed choice
  # and is deliberate: this rung reaps a live rank, so a blind probe must never
  # be grounds to tear one down.
  mlx-cluster-wired-ceiling = pkgs.runCommand "check-mlx-cluster-wired-ceiling" {
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
  } "bash ${src}/tests/test-rank-wired-ceiling.sh && touch $out";
}
