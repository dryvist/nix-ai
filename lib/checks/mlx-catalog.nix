# Catalog compile regression tests (programs.mlx.catalog -> per-model surfaces)
{ pkgs, hmConfigCatalog }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  # Catalog compile regression (programs.mlx.catalog -> per-model surfaces).
  # Uses hmConfigCatalog (lib/checks.nix): optiq+coder resident, gpt-oss+80B
  # swap (80B with a ttl tweak), plus a direct host override on optiq's
  # cacheMemoryMb that must beat the catalog's mkDefault.
  mlx-catalog =
    let
      c = hmConfigCatalog.config.programs.mlx;
      optiq = "mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit";
      coder = "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit";
      gptOss = "mlx-community/gpt-oss-120b-MXFP4-Q8";
      next80 = "mlx-community/Qwen3-Next-80B-A3B-Thinking-4bit";
      next80Instruct = "mlx-community/Qwen3-Next-80B-A3B-Instruct-4bit";
      qwen36 = "mlx-community/Qwen3.6-35B-A3B-4bit";
      judge27b = "mlx-community/Qwen3.8-27B-4bit";
      optiqFlags = c.modelFlagOverrides.${optiq};
      judgeArgs = builtins.concatStringsSep " " c.modelExtraArgs.${judge27b};
      commandBuilder = import ../../modules/mlx/model-server-cmd.nix {
        inherit (pkgs) lib;
        cfg = c;
        mlxModelServerPkg = pkgs.writeShellScriptBin "mlx-model-server" "";
      };
      optiqCmd =
        commandBuilder.mkModelCmd optiq + " " + pkgs.lib.escapeShellArgs c.modelExtraArgs.${optiq};
      judgeCmd =
        commandBuilder.mkModelCmd judge27b + " " + pkgs.lib.escapeShellArgs c.modelExtraArgs.${judge27b};
      uncataloguedCmd = commandBuilder.mkModelCmd "mlx-community/test-model";
      # Assert the EMITTED flags equal the DECLARED concurrency, not a literal.
      # A check pinning a magic number is what kept --decode-concurrency
      # hard-coded at 1 while proxy.concurrencyLimit said 4.
      conc = modelId: toString (commandBuilder.effectiveConcurrency modelId);
      # Same reason as `conc`: derive, never pin a literal. The emitted byte
      # figure is model-server-cmd's effectiveMlxLmCacheMb, which tracks the
      # catalog class's declared cacheMemoryMb (clamped to 16 GiB). A hardcoded
      # number here turns any legitimate class retune into a CI break — which is
      # exactly what happened when the 27B entry moved from an 8 GiB judge
      # profile to a 16 GiB large-context profile.
      cacheBytes =
        modelId:
        let
          mb = c.modelFlagOverrides.${modelId}.cacheMemoryMb or c.cacheMemoryMb;
        in
        toString ((if mb == null then 8192 else pkgs.lib.min mb 16384) * 1024 * 1024);
      nullDefaultsCmd =
        (import ../../modules/mlx/model-server-cmd.nix {
          inherit (pkgs) lib;
          cfg = c // {
            maxTokens = null;
            cacheMemoryMb = null;
          };
          mlxModelServerPkg = pkgs.writeShellScriptBin "mlx-model-server" "";
        }).mkModelCmd
          "mlx-community/null-default-test";
      watchdogAgent = hmConfigCatalog.config.launchd.agents.mlx-model-server-watchdog;
      inst = c.modelFlagOverrides.${next80Instruct};
      next80InstructPagedOff = inst.pagedKvCache == false && inst.enablePrefixCaching == false;
    in
    assert
      optiqFlags.cacheMemoryMb == 8192
      || throw "catalog: direct host override (8192) must beat the catalog default 16384, got ${toString optiqFlags.cacheMemoryMb}";
    assert
      optiqFlags.pagedCacheBlockSize == 512 && optiqFlags.maxNumSeqs == 8
      || throw "catalog: optiq resident profile (block 512 / maxNumSeqs 8) not compiled";
    assert
      builtins.match ".*--decode-concurrency ${conc optiq}.*--prompt-concurrency ${conc optiq}.*" optiqCmd
      != null
      && builtins.match ".*--tool-call-parser.*" optiqCmd == null
      || throw "catalog: official mlx_lm serial-serving args not compiled cleanly: ${optiqCmd}";
    assert
      c.modelFlagOverrides.${coder}.maxRequestTokens == 32768
      || throw "catalog: coder resident maxRequestTokens 32768 not compiled";
    assert
      c.modelContextWindows.${judge27b} == 131072
      || throw "catalog: Qwen3.8 must compile its 131072-token production window";
    assert
      c.modelFlagOverrides.${judge27b}.maxRequestTokens == 131072
      || throw "catalog: Qwen3.8 must admit its declared 131072-token production window";
    assert
      c.modelContextWindows.${qwen36} == 65536
      || throw "catalog: Qwen3.6 must advertise its 65536-token declared window";
    assert
      c.modelServerBackend == "mlx-lm"
      || throw "catalog: the goal judge must use the selected mlx_lm.server deployment path";
    assert
      c.enabledBackends == [ "mlx-lm" ]
      || throw "catalog: official mlx-lm must be the only enabled backend; vllm-mlx must remain preserved but disabled";
    # The watchdog is the only thing that notices a proxy that is up but not
    # serving, so on a host with a resident set it MUST be running. This used
    # to assert the opposite — that it stay disabled — back when its busy
    # handling depended on a vllm-only progress metric. The dependency now
    # lives behind MLX_WATCHDOG_BUSY_ESCALATION, so the intent is re-expressed
    # rather than dropped: enabled everywhere, and pinned to "alert" on the
    # backend that publishes no such metric, which is what keeps it from
    # reaping a brain that is merely saturating its slots.
    assert
      watchdogAgent.enable
      || throw "catalog: the serving watchdog must be enabled — a resident set with no watchdog has nothing supervising an up-but-not-serving proxy";
    assert
      watchdogAgent.config.EnvironmentVariables.MLX_WATCHDOG_BUSY_ESCALATION == "alert"
      || throw "catalog: mlx-lm exposes no engine-progress metric, so an expired busy grace must page (\"alert\"), never run the restart ladder against a saturated brain";
    # The 27B entry MUST NOT pin concurrency. It used to: as a latency-sensitive
    # judge beside a resident 80B it carried concurrencyLimit = 1. That entry is
    # gone, and this one is shaped as a fleet brain — so a pin of 1 makes
    # llama-swap serialize every request on any host where it is resident. That
    # regression shipped once and was caught only by reading the deployed
    # llama-swap.json, so assert the absence rather than a value: an entry with
    # no pin inherits proxy.concurrencyLimit, which is the intended contract.
    # The reasoning effort must be PINNED EXPLICITLY, to one of the two values
    # measured to finish. The chat template defaults reasoning_effort to
    # 'xhigh' when no kwarg is passed, and at xhigh this model exhausted
    # max_tokens without emitting a single answer character on 3 of 3 measured
    # runs. So an entry carrying no chat-template kwarg reads as
    # "unconfigured" but serves as "never answers" — absence is the failure,
    # which is why this asserts presence rather than trusting a default.
    #
    # low and medium are both accepted: both were measured to finish
    # (finish_reason "stop"), and which one serves is a tuning decision that
    # should not require editing a regression check. xhigh is excluded by
    # construction, since it matches neither alternative.
    assert
      !(builtins.hasAttr judge27b c.modelConcurrencyLimits)
      && builtins.match ".*reasoning_effort.*(low|medium).*" judgeArgs != null
      || throw "catalog: the 27B entry must not pin concurrency (a pin of 1 serializes every request where it is resident) and must pin reasoning_effort to low or medium (unset defaults to xhigh, which never finishes)";
    assert
      builtins.match ".*mlx-model-server --model mlx-community/Qwen3.8-27B-4bit.*" judgeCmd != null
      && builtins.match ".*--log-level INFO.*" judgeCmd != null
      && builtins.match ".*--max-tokens 8192.*" judgeCmd != null
      && builtins.match ".*--decode-concurrency ${conc judge27b}.*" judgeCmd != null
      && builtins.match ".*--prompt-concurrency ${conc judge27b}.*" judgeCmd != null
      && builtins.match ".*--prompt-cache-size 4.*" judgeCmd != null
      && builtins.match ".*--prompt-cache-bytes ${cacheBytes judge27b}.*" judgeCmd != null
      && builtins.match ".*vllm-mlx.*" judgeCmd == null
      && builtins.match ".*--gpu-memory-utilization.*" judgeCmd == null
      || throw "catalog: 27B judge command must use only the bounded official mlx_lm serving contract: ${judgeCmd}";
    assert
      builtins.match ".*--log-level INFO.*" uncataloguedCmd != null
      && builtins.match ".*--max-tokens 8192.*" uncataloguedCmd != null
      &&
        builtins.match ".*--decode-concurrency ${conc "mlx-community/test-model"}.*" uncataloguedCmd != null
      &&
        builtins.match ".*--prompt-concurrency ${conc "mlx-community/test-model"}.*" uncataloguedCmd != null
      && builtins.match ".*--prompt-cache-size 4.*" uncataloguedCmd != null
      && builtins.match ".*--prompt-cache-bytes 8589934592.*" uncataloguedCmd != null
      || throw "catalog: non-catalog official workers must inherit the same bounded serial contract: ${uncataloguedCmd}";
    assert
      builtins.match ".*--max-tokens 8192.*" nullDefaultsCmd != null
      && builtins.match ".*--prompt-cache-bytes 8589934592.*" nullDefaultsCmd != null
      || throw "catalog: nullable legacy settings must retain bounded official mlx_lm defaults: ${nullDefaultsCmd}";
    assert
      c.proxy.logLevel == "info"
      || throw "catalog: production proxy logging must remain prompt-safe INFO";
    # The proxy's request lines are the only record of which client received a
    # 429 or 502. Upstream leaves them untimestamped, which makes them
    # impossible to correlate with a fleet-side failure at a known instant —
    # observed 2026-09-01 while trying to attribute cron failures to the tier.
    # A non-empty layout is the whole point of the option; an empty one silently
    # restores the ambiguity.
    assert
      c.proxy.logTimeFormat != ""
      || throw "catalog: proxy request lines must carry a timestamp or they cannot be correlated with anything";
    assert
      hmConfigCatalog.config.services.aiStack.roleOverrides.goal-judge == judge27b
      || throw "catalog: logical goal-judge role must resolve to the catalog-owned physical model";
    assert
      !(builtins.hasAttr judge27b c.modelTtls)
      || throw "catalog: resident 27B judge must inherit the resident TTL";
    assert
      c.modelTtls."mlx-community/Qwen3.5-9B-OptiQ-4bit" == 900
      || throw "catalog: swap-class role models must retain a backend-neutral 900-second proxy TTL";
    assert
      c.modelFlagOverrides.${gptOss}.pagedKvCache == false
      && c.modelFlagOverrides.${gptOss}.enablePrefixCaching == false
      || throw "catalog: gpt-oss swap profile must disable paged KV + prefix caching";
    assert
      c.models.${gptOss}.ttl == 900
      || throw "catalog: gpt-oss swap ttl must default to 900, got ${toString c.models.${gptOss}.ttl}";
    assert
      c.models.${next80}.ttl == 600 && c.modelFlagOverrides.${next80}.autoUnloadIdleSeconds == 600
      || throw "catalog: 80B ttl tweak (600) must reach both llama-swap ttl and worker idle unload";
    assert
      builtins.match ".*enable_thinking.*" (builtins.concatStringsSep " " c.models.${next80}.extraArgs)
      == null
      || throw "catalog: 80B (always-thinking variant) must not carry an enable_thinking kwarg";
    assert
      c.modelFlagOverrides.${next80}.pagedKvCache == false
      && c.modelFlagOverrides.${next80}.enablePrefixCaching == false
      || throw "catalog: 80B-thinking (qwen3_next hybrid) must disable paged KV + prefix caching — paged-block reconstruction fails every multi-turn request and wedges the worker (mlx-lm#1162)";
    assert
      next80InstructPagedOff
      || throw "catalog: 80B-instruct (qwen3_next hybrid) must disable paged KV + prefix caching (mlx-lm#1162)";
    # 40B+ single-slot policy (user directive 2026-07-21): every 40B+ model
    # compiles concurrencyLimit=1 so llama-swap serializes dispatch. The hybrid
    # 80Bs abort under concurrent dispatch (Metal resource-limit) and gpt-oss is
    # 63 GB on one GPU; batching only time-slices and balloons latency into the
    # 429 storm. maxNumSeqs=1 in the catalog flags is the paired engine-level
    # guard. Extended from the 2026-07 Instruct-only serialization.
    assert
      c.modelConcurrencyLimits.${next80Instruct} == 1
      || throw "catalog: 80B-instruct must compile concurrencyLimit=1 (40B+ single-slot policy)";
    assert
      c.modelConcurrencyLimits.${next80} == 1
      || throw "catalog: 80B-thinking must compile concurrencyLimit=1 (40B+ single-slot policy)";
    assert
      c.modelConcurrencyLimits.${gptOss} == 1
      || throw "catalog: gpt-oss-120b must compile concurrencyLimit=1 (40B+ single-slot policy)";
    helpers.mkMarker "check-mlx-catalog" "MLX catalog: resident/swap compile, bounded tweak, ttl fan-out, and host-override precedence verified";
}
