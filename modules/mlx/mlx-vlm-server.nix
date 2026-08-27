# Vision-language serving path — mlx-vlm behind ./scripts/mlx-vlm-adapter.py.
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
# WHY NOT mlx_vlm.server, WHICH ALREADY EXISTS: it runs generation on a worker
# thread, and a model whose own implementation forces a GPU sync while building
# input embeddings then fails every request with
# "RuntimeError: There is no Stream(gpu, 2) in current thread".
# Measured against mlx-vlm 0.6.13 (latest at time of writing) with the OCR
# entry in ./catalog-data.nix — which is the only place a physical id belongs,
# so this note names the behaviour rather than the id: the model loads,
# one-shot mlx_vlm.generate() returns correct OCR, and every mlx_vlm.server
# request fails. --max-num-seqs 1 does not avoid it — the failure is the
# threading model, not batch width. The adapter keeps the same wire contract
# and runs generation on the main thread instead. Full rationale in the
# script's docstring; revisit if upstream fixes the threading path.
#
# The binary is named "mlx-model-server" to match the vllm-mlx adapter and the
# mlx-lm launcher: llama-swap's cmd contract is identical across backends, so
# the name that appears in argv should be too. Process-pattern matching does
# NOT key off this name — see ./model-server-pattern.nix, which matches the
# script path instead and must list every backend that can have a live worker.
#
# mlx-vlm is pinned once in lib/versions.nix and shared with the
# mlx-vlm-generate CLI in ./packages.nix; this reuses that pin rather than
# introducing a second one that could drift.
{
  pkgs,
  mlxVlmVersion,
  uvPythonVersion,
}:
let
  adapter = ./scripts/mlx-vlm-adapter.py;
in
{
  pkg = pkgs.writeShellScriptBin "mlx-model-server" ''
    exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "mlx-vlm==${mlxVlmVersion}" python ${adapter} "$@"
  '';

  nativePkg = pkgs.writeShellScriptBin "mlx-vlm-native-server" ''
    exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "mlx-vlm==${mlxVlmVersion}" python -m mlx_vlm.server "$@"
  '';

  # The single source ./model-server-pattern.nix derives its mlx-vlm entry
  # from, mirroring mlx-lm-server.nix. Derived, never hand-typed: a literal is
  # exactly what silently drifted from the real invocation before, leaving
  # every pattern-based reap a no-op.
  launchScriptBasename = builtins.baseNameOf (toString adapter);
  nativeLaunchScriptBasename = "mlx-vlm-native-server";
}
