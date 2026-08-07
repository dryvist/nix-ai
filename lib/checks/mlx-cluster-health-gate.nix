# vk1188: the automated rank health gate + soak. Split into its own file
# rather than added to ./mlx-cluster-scripts.nix, which was already close to
# the 12KB error ceiling in .file-size.yml — same split-rather-than-exempt
# pattern as ./mlx-cluster-mem-headroom.nix.
{
  pkgs,
  src,
}:
{
  # THE CHECK THAT FAILS IF THE AUTOMATED GATE STOPS ACTUALLY GATING. Sources
  # the shipped guards + gate in the module's concatenation order. curl is
  # stubbed as a shell function (this file's own process runs the sourced
  # probes directly, same idiom test-mem-headroom.sh uses for curl in
  # alert()); vm_stat is a generated executable, same fixture writer as
  # test-mem-headroom.sh. Asserts all four probes (models 200, non-empty
  # completion under a real timeout, N-at-once, wired-vs-ceiling), that a
  # single failed probe fails the whole gate, that every run appends evidence
  # rather than overwriting it, and that the soak recheck exercises probe (b)
  # alone.
  mlx-cluster-health-gate = pkgs.runCommand "check-mlx-cluster-health-gate" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
    ];
    GUARDS = "${src}/modules/mlx/scripts/cluster-link-guards.sh";
    GATE = "${src}/modules/mlx/scripts/cluster-health-gate.sh";
  } "bash ${src}/tests/test-health-gate.sh && touch $out";
}
