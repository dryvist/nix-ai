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
{ lib, ... }:
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
      concurrencyLimit = lib.mkOption {
        type = lib.types.ints.positive;
        default = 4;
        description = ''
          Max in-flight requests llama-swap will forward to a model server per
          model. Maps directly to the YAML key llama-swap reads
          (`concurrencyLimit`); excess requests get HTTP 429.

          Default 4 — matches `maxNumSeqs` so continuous batching is fed.
          Re-raised from 2 on 2026-07-11 after a replicated c1-c8 sweep
          (MBP Coder-30B): zero errors within the limit, 1.6-2.3x
          aggregate when the batcher engages, worst case serialization
          (~1.0x). Scheduling is bimodal, so treat >1x as opportunistic
          and keep bench drivers pinned to their documented concurrency
          (mlx-benchmarks RUNBOOK). The pipe-timeout storm behind the old
          4->2 tightening predated the maxRequestTokens hardening that
          fixed its cause. Above the limit callers get 429 — cap or
          retry with backoff; the llm_router tier absorbs 429s via its
          retry policy. Setting this to 1 silently defeats batching.
        '';
      };
    };
  };
}
