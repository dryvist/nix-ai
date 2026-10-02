# Backend-selection contract for the MLX serving catalog.
#
# Split out of ./mlx-catalog.nix to stay under the .file-size.yml ceiling, the
# same reason mlx-wedge-metricsfree.nix is its own file. The split is by
# responsibility: this file asserts WHICH backend may be selected and on what
# terms; mlx-catalog.nix asserts what the selected backend then compiles to.
{ pkgs, hmConfigCatalog }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  mlx-backend-selection =
    let
      c = hmConfigCatalog.config.programs.mlx;
    in
    # The selected backend must be one of the enabled ones.
    assert
      builtins.elem c.modelServerBackend c.enabledBackends
      || throw "catalog: the selected modelServerBackend must be listed in enabledBackends";
    helpers.mkMarker "check-mlx-backend-selection" "MLX backend selection: the selected backend is enabled";
}
