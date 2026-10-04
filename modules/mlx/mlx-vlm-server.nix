# Vision-language serving path plus native mlx-vlm MTP profiles.
#
# Split out of ./default.nix at the repo per-file size cap, the same move
# ./mlx-lm-server.nix and ./worker-env.nix already made.
#
# mlx-vlm is pinned once in lib/versions.nix and shared with the
# mlx-vlm-generate CLI in ./packages.nix.
{
  pkgs,
  mlxVlmVersion,
  uvPythonVersion,
}:
{
  pkg = pkgs.writeShellScriptBin "mlx-model-server" ''
    exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "mlx-vlm==${mlxVlmVersion}" python ${./scripts/mlx-vlm-adapter.py} "$@"
  '';

  nativePkg = pkgs.writeShellScriptBin "mlx-vlm-native-server" ''
    exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "mlx-vlm==${mlxVlmVersion}" python -m mlx_vlm.server "$@"
  '';

  launchScriptBasename = builtins.baseNameOf (toString ./scripts/mlx-vlm-adapter.py);
  nativeLaunchScriptBasename = "mlx-vlm-native-server";
}
