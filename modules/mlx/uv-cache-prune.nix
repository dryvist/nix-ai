{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.mlx;

  # writeShellApplication rather than a bare `bash script.sh` in the activation
  # snippet, so the script gets a PATH carrying the tools it calls. Activation
  # runs with a minimal PATH: the first version invoked `pgrep`, `du`, and `cut`
  # bare, and `pgrep: command not found` made the live-worker guard evaluate
  # FALSE (set -e does not fire on a failing `if` condition), so it would have
  # pruned with a model loaded. runtimeInputs fixes du/cut; pgrep stays an
  # absolute system path inside the script, because Darwin's procps does not
  # ship it.
  pruneScript = pkgs.writeShellApplication {
    name = "mlx-uv-cache-prune";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./scripts/uv-cache-prune.sh;
  };
in
{
  # Reclaim stranded uv venvs on every `darwin-rebuild switch`. Rationale,
  # measurements, and the live-worker guard live in the script itself.
  config = lib.mkIf cfg.enable {
    home.activation.mlxUvCachePrune = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe pruneScript} ${pkgs.uv}/bin/uv || true
    '';
  };
}
