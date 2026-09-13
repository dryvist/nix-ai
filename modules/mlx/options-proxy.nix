#
# MLX Module — model-swap proxy options (llama-swap)
#
# Split from options-runtime.nix for the 12KB file-size gate; see the split
# history of modules/mlx/options for the pattern.
#
# llama-swap sits on the API port and manages MLX model servers as child
# processes. Model switching is transparent: send a request with model: "X"
# and the proxy handles it.
#
{ lib, config, ... }:
let
  # concurrencyLimit ceiling — derived from the residency budget, not chosen.
  #
  # A worker's memory budget is programs.mlx.memoryHardLimitGb itself (see
  # modules/mlx/options-residency.nix) — read live so this adapts per host
  # instead of assuming the Studio's k=2/100 GiB shape.
  perWorkerBudgetGiB = config.programs.mlx.memoryHardLimitGb;
  # Peak 4-bit weight footprint in this registry (the 35B-class model,
  # modules/mlx/catalog-data.nix), rounded up to the next whole GiB —
  # the conservative direction, so this stays a ceiling.
  peakWeightGiB = 31;
  # Dense-attention KV cache cost per token, the pessimistic bound (MoE
  # families cost less, at 20 KiB/token). See docs/architecture/mlx-stack.md.
  kvPerTokenDenseKiB = 64;
  # Largest catalog context window actually compiled into a selected model.
  # One in-flight request at this ceiling sets the largest KV reservation to
  # budget for. maxRequestTokens is a vllm generation guard, not an MLX-LM
  # context declaration, so it must not stand in for this calculation.
  configuredContextWindows = lib.attrValues config.programs.mlx.modelContextWindows;
  maxGrantedRequestTokens = lib.foldl' lib.max 32768 configuredContextWindows;
  kvPerSeqGiB = (kvPerTokenDenseKiB * maxGrantedRequestTokens) / (1024 * 1024);
  # Memory-only headroom after the peak weight, sliced into pessimistic-KV
  # portions: how many concurrent max-length requests the budget FITS.
  # Fitting in memory is necessary but not sufficient — concurrencyLimit also
  # sets --decode-concurrency/--prompt-concurrency on Apple Silicon's single
  # GPU, where throughput collapses well before memory runs out. 4 is that
  # separate operator judgment about practical decode concurrency, not a
  # memory bound, so it caps the memory-derived value rather than replacing
  # it: tighten on memory, never loosen past operator judgment.
  operatorConcurrencyCap = 4;
  memoryFitCeiling = lib.max 1 ((perWorkerBudgetGiB - peakWeightGiB) / kvPerSeqGiB);
  concurrencyLimitCeiling = lib.min operatorConcurrencyCap memoryFitCeiling;
in
{
  options.programs.mlx = {
    proxy = {
      # groupSwap — llama-swap `groups.mlx-models.swap`. true (default) keeps
      # the one-resident-model posture: loading any model evicts the previous
      # one, so swap-thrash is impossible on RAM-constrained workstations.
      # false lets multiple registry models stay resident concurrently
      # (server-class hosts serving e.g. a large default plus a coder model);
      # the memory bound then falls to the selected server's cache budget plus
      # the host wired-memory ceiling. The host must size the resident sum.
      groupSwap = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether llama-swap unloads the resident model before loading another (groups.mlx-models.swap). Set false on hosts with the memory headroom to keep several models resident at once.";
      };

      healthCheckTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 180;
        description = "Seconds to wait for a backend to become healthy. 70GB models take 20-60s to load; 180s covers the worst case.";
      };
      responseHeaderTimeout = lib.mkOption {
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
      idleTtl = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 900;
        description = "Idle TTL in seconds applied uniformly to every model in the registry (including the default-aliased one). 0 = never auto-unload (escape hatch). Default 900 s (15 min). Tightened twice: 3600 -> 1800 after the recurring `nix-ai#801` stuck-past-TTL incidents, then 1800 -> 900 after the 2026-06-10 nix-mac-performance RC14 snapshot showed a single healthy in-TTL ~50 GB worker plus the desktop working set saturating compressor + swap on a 128 GB host — idle-weight dwell is the dominant memory cost, and a 4-bit MoE model reloads from NVMe in 10-20 s, so eviction is cheap relative to the host-wide paging it prevents.";
      };
      logLevel = lib.mkOption {
        type = lib.types.enum [
          "debug"
          "info"
          "warn"
          "error"
        ];
        default = "info";
        description = ''
          llama-swap log verbosity. "info" is the production default: it keeps
          model load, unload, and routing events without logging proxied
          request or response bodies. "debug" is for supervised diagnosis
          only because it can contain prompt and completion content.
        '';
      };
      logToStdout = lib.mkOption {
        type = lib.types.enum [
          "proxy"
          "upstream"
          "both"
          "none"
        ];
        default = "both";
        description = ''
          Which output streams llama-swap forwards to stdout (and therefore
          the /logs/stream SSE endpoint). "both" interleaves proxy events with
          selected MLX model-server output.
        '';
      };
      logTimeFormat = lib.mkOption {
        type = lib.types.str;
        default = "2006-01-02T15:04:05Z07:00";
        example = "";
        description = ''
          Go time layout stamped on llama-swap's own log lines. Upstream
          defaults this to the empty string, which emits request lines
          carrying client address, path, status and duration but NO time —
          so a rejection cannot be tied to the moment it happened.

          That gap is not cosmetic. The proxy's request lines are the only
          record of which client got a 429 or a 502, while the MLX servers'
          own lines beneath them ARE timestamped but show only the loopback
          address of the proxy. Correlating a fleet-side failure against the
          serving tier therefore has no shared axis: one side has identity
          without time, the other time without identity.

          The default here is RFC 3339 with offset, matching the timestamps
          the rest of the estate's alarms and journals use, so a failure at a
          known instant can be looked up directly. Set to "" to restore
          upstream's untimestamped behaviour.
        '';
      };
      concurrencyLimit = lib.mkOption {
        # The ceiling is derived above from the residency budget, then capped
        # at operatorConcurrencyCap (throughput, not memory, is the limit
        # past that point) — expressed in the type so a value the hardware
        # cannot honor cannot be represented rather than merely remembered.
        type = lib.types.ints.between 1 concurrencyLimitCeiling;
        default = 1;
        description = ''
          Max in-flight requests llama-swap will forward to a model server per
          model. Maps directly to the YAML key llama-swap reads
          (`concurrencyLimit`); excess requests get HTTP 429.

          This is the SINGLE definition of per-model concurrency. It feeds both
          llama-swap's advertised limit and the MLX server's own
          --decode-concurrency/--prompt-concurrency (see
          model-server-cmd.nix `effectiveConcurrency`). Do not set either
          consumer independently — that split is what produced the 2026-07-24
          cron kills: the proxy admitted 4 while the server served 1, and the
          excess came back as 429.

          Default 1, ceiling ${toString concurrencyLimitCeiling} on this host:
          min(operatorConcurrencyCap = ${toString operatorConcurrencyCap}, memory fit
          = ${toString memoryFitCeiling}). Memory fit derives from
          programs.mlx.memoryHardLimitGb (currently ${toString perWorkerBudgetGiB} GiB)
          — the largest number of concurrent maxGrantedRequestTokens-length
          requests the worker's memory budget can hold after the peak
          resident model's own weight footprint. The operator cap holds
          regardless: more requests would fit in memory long before Apple
          Silicon's single GPU could actually decode them concurrently. 1 serializes and
          defeats continuous batching; that is the accepted trade while the
          simplest non-crashing configuration is the goal. Raising it means
          raising the server's real capacity at the same time, which now
          happens automatically because both derive from here.

          Above the limit callers get 429 — cap or retry with backoff; the
          llm_router tier absorbs 429s via its retry policy. Prior sweep data
          (2026-07-11, MBP Coder-30B, c1-c8) measured 1.6-2.3x aggregate when
          the batcher engages, worst case ~1.0x; scheduling is bimodal, so
          treat >1x as opportunistic and keep bench drivers pinned to their
          documented concurrency (mlx-benchmarks RUNBOOK).
        '';
      };
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
