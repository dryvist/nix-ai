# Standalone serving restoration used by join recovery and detach.
{
  pkgs,
  src,
}:
{
  mlx-cluster-serving-restore = pkgs.runCommand "check-mlx-cluster-serving-restore" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
  } "cd ${src} && bash tests/test-serving-restore.sh && touch $out";
}
