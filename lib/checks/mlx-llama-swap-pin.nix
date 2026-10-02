# The llama-swap the MLX module installs is the release pinned in
# lib/versions.nix. Renovate moves that pin; modules/mlx/llama-swap.nix builds
# it. A module that falls back to plain nixpkgs, which trails upstream, fails
# here instead of silently serving an older proxy.
{ pkgs, hmConfig }:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };
  want = lib.removePrefix "v" (import ../versions.nix).llamaSwap;
  installed = map (p: p.version) (
    builtins.filter (p: (p.pname or "") == "llama-swap") hmConfig.config.home.packages
  );
in
{
  mlx-llama-swap-pin =
    assert
      installed == [ want ]
      || throw "mlx: home.packages carries llama-swap ${builtins.toJSON installed}, expected exactly [ \"${want}\" ] from lib/versions.nix llamaSwap";
    helpers.mkMarker "check-mlx-llama-swap-pin" "MLX: llama-swap ${want} matches the lib/versions.nix pin";
}
