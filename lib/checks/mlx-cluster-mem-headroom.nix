# Free-memory and wired-headroom gates used at J5.
{
  pkgs,
  src,
}:
{
  mlx-cluster-mem-headroom = pkgs.runCommand "check-mlx-cluster-mem-headroom" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
    ];
  } "cd ${src} && bash tests/test-mem-headroom.sh && touch $out";
}
