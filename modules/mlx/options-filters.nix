#
# MLX Module — llama-swap request filter options
#
# Per-model filters applied at the llama-swap proxy layer. Filters run BEFORE
# the request reaches vllm-mlx, so they apply universally — to every caller,
# every prompt, every model with the filter configured. Cannot be bypassed
# by client request bodies.
#
# Two filter types are supported by llama-swap:
#
#   setParams   — dict of parameters to SET/OVERRIDE in the request.
#                 Enforcement, not default-filling. If the client sends
#                 frequency_penalty=0 and setParams.frequency_penalty=0.3,
#                 the request that reaches vllm-mlx has 0.3.
#
#   stripParams — comma-separated list of parameters to REMOVE from the
#                 request before forwarding. Useful to fully delegate a
#                 parameter to the vllm-mlx / model default.
#
# Reference: https://github.com/mostlygeek/llama-swap/blob/main/docs/configuration.md
#
# Why the default value enables modest frequency_penalty/presence_penalty:
#
# Token-repetition loops on local MLX models are most commonly caused by
# callers using greedy decoding (temperature=0) on long inputs (e.g.
# transcript summarization). The OpenAI-API standard counter-measures are
# frequency_penalty (additive penalty proportional to a token's occurrence
# count) and presence_penalty (additive penalty for any previously-seen
# token). Both flow cleanly through vllm-mlx → mlx-lm. A modest value of
# 0.3 (in the 0.0-2.0 range) disrupts the high-probability token cycles
# that produce loops without measurably degrading quality on normal
# prompts. Higher values trade quality for safety; lower values approach
# the unprotected baseline. 0.3 is the community-recognized "loop-
# prevention baseline" for OpenAI-compatible serving stacks.
#
# Documented at:
#   - https://github.com/mostlygeek/llama-swap/blob/main/docs/configuration.md
#   - https://github.com/mostlygeek/llama-swap/blob/main/config.example.yaml
#
{ lib, ... }:
{
  options.programs.mlx.proxy.defaultFilters = lib.mkOption {
    type = lib.types.attrs;
    default = {
      setParams = {
        frequency_penalty = 0.3;
        presence_penalty = 0.3;
      };
    };
    description = ''
      llama-swap filters merged into every model in the generated config.
      The default enables modest OpenAI-spec frequency/presence penalties to
      prevent token-repetition loops on every request, including from clients
      that explicitly send greedy-decoding parameters (the filter overrides
      them). Set to {} to disable entirely; per-model overrides are supported
      via programs.mlx.models.<name>.filters.
    '';
    example = lib.literalExpression ''
      {
        setParams = {
          frequency_penalty = 0.5;
          presence_penalty = 0.3;
          top_p = 0.95;
        };
        stripParams = "temperature";
      }
    '';
  };
}
