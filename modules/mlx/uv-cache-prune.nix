{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.mlx;
in
{
  # Reclaim stranded uv venvs on every `darwin-rebuild switch`. Rationale,
  # measurements, and the live-worker guard live in the script itself.
  config = lib.mkIf cfg.enable {
    home.activation.mlxUvCachePrune = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.bash}/bin/bash ${./scripts/uv-cache-prune.sh} ${pkgs.uv}/bin/uv || true
    '';
  };
}
