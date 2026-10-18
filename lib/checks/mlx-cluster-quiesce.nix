# Coordinator app and launchd quiesce behavior.
{
  pkgs,
  src,
}:
{
  mlx-cluster-quiesce = pkgs.runCommand "check-mlx-cluster-quiesce" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
      pkgs.gnused
    ];
  } "cd ${src} && bash tests/test-quiesce.sh && touch $out";
}
