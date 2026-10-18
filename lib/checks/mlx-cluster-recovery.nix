# Teardown ordering, survivor safety, SIGKILL exit status, and label recovery.
{
  pkgs,
  src,
}:
{
  mlx-cluster-teardown-recovery = pkgs.runCommand "check-mlx-cluster-teardown-recovery" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
    ];
  } "cd ${src} && bash tests/test-teardown-recovery.sh && touch $out";
}
