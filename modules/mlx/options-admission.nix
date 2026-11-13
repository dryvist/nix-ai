{ config, lib, ... }:
{
  options.programs.mlx.modelAdmissionLimits = lib.mkOption {
    type = lib.types.attrsOf lib.types.ints.positive;
    example = lib.literalExpression ''
      {
        "mlx-community/<model>" = 26;
      }
    '';
    description = ''
      Per-physical-model admission limit, keyed by physical model id: the
      requests admitted for the model, active plus bounded worker waiters. It
      is separate from modelConcurrencyLimits, which sets the MLX worker's
      decode/prompt concurrency. By default, admission matches the worker
      limit; catalog entries can raise it to the worker's bounded queue
      capacity plus active requests. LiteLLM's per-route max_parallel_requests
      does not read this option; it follows modelConcurrencyLimits, so a
      request beyond the worker's width falls through to the next rung.
    '';
  };

  config.programs.mlx.modelAdmissionLimits = lib.mkOverride 1500 config.programs.mlx.modelConcurrencyLimits;
}
