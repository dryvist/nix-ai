{
  pkgs,
  src,
}:
{
  mlx-cluster-pd-gate = pkgs.runCommand "check-mlx-cluster-pd-gate" {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    STATUS = "${src}/modules/mlx/scripts/cluster-rank-status.sh";
    PD_COUNT = "${src}/modules/mlx/scripts/cluster-pd-count.sh";
    PD_GATE = "${src}/modules/mlx/scripts/cluster-pd-gate.sh";
  } "bash ${src}/tests/test-pd-gate.sh && touch $out";
}
