# Negative test for the modules/mlx/assertions.nix modelExtraArgs check: a
# key that doesn't match a role-registry physical id must be flagged, and a
# key that does match must not. Same detection logic as that assertion — if
# it changes there, it must change here too. Split from mlx.nix at the
# 12,288-byte file-size gate.
{ pkgs }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  registryPhysicalIds = [
    "mlx-community/model-a"
    "mlx-community/model-b"
  ];
  badKeysOf =
    extraArgs:
    builtins.filter (key: !(builtins.elem key registryPhysicalIds)) (builtins.attrNames extraArgs);
  validCase = badKeysOf { "mlx-community/model-a" = [ "--flag" ]; };
  typoCase = badKeysOf { "mlx-comunity/model-a" = [ "--flag" ]; };
in
{
  mlx-model-extra-args-key-negative =
    assert validCase == [ ] || throw "modelExtraArgs negative: registered key wrongly flagged";
    assert
      typoCase == [ "mlx-comunity/model-a" ]
      || throw "modelExtraArgs negative: typo'd key not flagged — the silent-drop bug would reproduce";
    helpers.mkMarker "check-mlx-model-extra-args-key-negative" "MLX modelExtraArgs: unregistered/typo'd physical-id keys verified detectable";
}
