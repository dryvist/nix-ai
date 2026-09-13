#
# MLX Module — llama-swap response-header timeout options
#
# Split from options-proxy.nix for the 12KB file-size gate; see the split
# history of modules/mlx/options for the pattern. Both options concern the
# same first-byte timeout (a global default plus its per-model override) so
# they stay together in their own file rather than splitting further.
#
{ lib, ... }:
{
  options.programs.mlx = {
    proxy.responseHeaderTimeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      # No direct measurement exists yet for the target model
      # (qwen38-27b, dense, 131072-token context) on the Mac Studio it
      # runs on. Until one does, scale the only prefill datapoint
      # available -- unpublished, from a 2026-07-19 mlx-benchmarks run,
      # index 8 (last row) of a 3-sample series: 667.44 tok/s (the
      # slowest of the three samples at that prompt length; the other
      # two were 724.3 and 683.9), Qwen3.6-35B-A3B-OptiQ-4bit, M4 Max,
      # prompt_tokens 2509 -- by the active-parameter ratio between that
      # MoE (3B active) and the target dense model (27B active), since
      # prefill is compute-bound in active parameters: 667 x 3/27 = 74
      # tok/s. Against the largest configured context window (131072
      # tokens): 131072 / 74 = 1771s worst-case first byte, x1.2 margin
      # = 2125s. Must stay under the router's own per-request timeout
      # (2400s, ai_router_request_timeout_seconds in ansible-proxmox-ai's
      # llm_router role), the binding upper constraint -- asserted in
      # assertions.nix.
      #
      # The same series shows prefill rate falling with prompt length
      # (597-token mean 1335.8 tok/s vs 2509-token mean 691.9 tok/s) --
      # a known, deliberately unmodelled effect the 1.2 margin above does
      # not cover. This estimate is a placeholder; a live time-to-first-
      # byte measurement on the real model/host/context replaces it
      # (tracked separately) and is the only way to close that gap.
      default = 2125;
      description = "Seconds llama-swap waits for a worker's first response byte before treating the request as failed (per-model timeouts.responseHeader). Upstream defaults this to zero, meaning never; this module previously left the timeouts key unset entirely, so every model inherited that unbounded wait. A worker that accepts a request and then stalls before writing anything back (a hung generation loop, not a crash, so the connection stays open) never returns from the reverse proxy call, so its admission slot never releases. Set to zero to restore the unbounded upstream default. Per-model override: programs.mlx.modelResponseHeaderTimeouts.";
    };

    # See proxy.responseHeaderTimeout's own comment for the derivation and
    # the timeout-ladder ordering this must not cross (asserted in
    # assertions.nix). Top-level sibling of proxy, matching
    # modelConcurrencyLimits' placement (options-runtime.nix) as the
    # per-model override for a global proxy.* default.
    modelResponseHeaderTimeouts = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.unsigned;
      default = { };
      example = lib.literalExpression ''
        {
          "mlx-community/<large-context-model>" = 600;
        }
      '';
      description = "Per-physical-model override of programs.mlx.proxy.responseHeaderTimeout, for a model whose own context window or measured prefill rate needs a different first-byte bound than the global default -- a small model wedged should not wait as long as a large model's legitimate cold prefill. Keyed by physical model id; absent id falls back to proxy.responseHeaderTimeout.";
    };
  };
}
