# Periodic orphan-reap agent — same reap functions as llama-swap-launch, run on
# a timer instead of only on the way up. See scripts/mlx-orphan-reap.sh for why
# a second caller exists and why it is safe to run while the proxy is serving.
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "mlx-orphan-reap";
  # Same reasoning as llama-swap-launch-pkg.nix: lsof/kill/ps are called by
  # absolute path, so no procps here.
  runtimeInputs = [ pkgs.coreutils ];
  text = lib.concatStringsSep "\n" [
    (builtins.readFile ./scripts/llama-swap-reap.sh)
    (builtins.readFile ./scripts/mlx-orphan-reap.sh)
  ];
}
