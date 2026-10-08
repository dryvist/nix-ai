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
      Per-physical-model llama-swap admission limit, keyed by physical model
      id. This is separate from modelConcurrencyLimits, which sets the MLX
      worker's decode/prompt concurrency. By default, admission matches the
      worker limit; catalog entries can raise it to the worker's bounded queue
      capacity plus active requests. Models without an override retain their
      existing limit, including serialized adapters such as OCR.
    '';
  };

  config.programs.mlx.modelAdmissionLimits = lib.mkOverride 1500 config.programs.mlx.modelConcurrencyLimits;
}
