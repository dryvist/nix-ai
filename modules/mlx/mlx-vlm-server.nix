# mlx_vlm.server wrapper — the vision-language serving path.
#
# Split out of ./default.nix at the repo per-file size cap, the same move
# ./mlx-lm-server.nix and ./worker-env.nix already made.
#
# WHY A SECOND SERVER AT ALL: mlx_lm.server exposes no image input, so a
# vision-language model cannot be served by it under any flag combination.
# Rather than switch a whole host, programs.mlx.modelBackends selects this
# binary per model (see ./model-server-cmd.nix), leaving every text model on
# the host backend untouched.
#
# The binary is named "mlx-model-server" to match the vllm-mlx adapter and the
# mlx-lm launcher: llama-swap's cmd contract is identical across backends, so
# the name that appears in argv should be too. Process-pattern matching does
# NOT key off this name — see ./model-server-pattern.nix, which matches the
# module path instead and must list every backend that can have a live worker.
#
# mlx-vlm is pinned once in lib/versions.nix and shared with the
# mlx-vlm-generate CLI in ./packages.nix; this reuses that pin rather than
# introducing a second one that could drift.
{
  pkgs,
  mlxVlmVersion,
  uvPythonVersion,
}:
{
  pkg = pkgs.writeShellScriptBin "mlx-model-server" ''
    exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "mlx-vlm==${mlxVlmVersion}" mlx_vlm.server "$@"
  '';
}
