# Per-model server-backend selection.
#
# Split out of ./options-runtime.nix at the repo per-file size cap, the same
# move the options-cluster-* family already made.
#
# WHY THIS EXISTS: programs.mlx.modelServerBackend is one value for a whole
# host, which was sufficient while every served model was a text LLM. It stops
# being sufficient the moment a host serves a vision-language model:
# mlx_lm.server exposes no image input under any flag combination, so such a
# model is unservable on the host backend rather than merely slow. Switching
# the whole host is not an option either — that would move every text model
# onto a backend tuned for none of them.
#
# So the backend resolves per model, with modelServerBackend as the fallback.
# An empty modelBackends therefore reproduces single-backend behaviour exactly,
# which is what keeps this change inert on every host that does not use it.
#
# SCOPE: this changes the worker binary and its flag set, nothing else. The
# proxy, the model registry, TTL and concurrency all stay backend-neutral and
# keep working off physical model ids. One thing that is NOT automatic:
# ./model-server-pattern.nix must list every backend that can have a live
# worker, or pattern-based reaps silently skip the ones it omits.
{ lib, ... }:
{
  options.programs.mlx.modelBackends = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.enum [
        "mlx-lm"
        "vllm-mlx"
        "mlx-vlm"
        "mlx-vlm-native"
      ]
    );
    default = { };
    example = lib.literalExpression ''
      {
        "mlx-community/<vision-language-model>" = "mlx-vlm";
      }
    '';
    description = "Per-physical-model override of programs.mlx.modelServerBackend, for models the host backend cannot serve (e.g. vision-language models needing mlx_vlm.server).";
  };
}
