# Catalog compile regression tests (programs.mlx.catalog -> per-model surfaces)
{ pkgs, hmConfigCatalog }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  # Catalog compile regression (programs.mlx.catalog -> per-model surfaces).
  # Uses hmConfigCatalog (lib/checks-fixtures.nix): 27B resident, MiMo and OCR
  # swap (OCR with a ttl tweak), plus a direct host override on the 27B's
  # cacheMemoryMb that must beat the catalog's mkDefault.
  mlx-catalog =
    let
      c = hmConfigCatalog.config.programs.mlx;
      mimo = "mlx-community/MiMo-V2.6-Distill-Qwen-9B-OptiQ-4bit";
      ocr = "mlx-community/Unlimited-OCR-bf16";
      judge27b = "mlx-community/Qwen3.8-27B-4bit";
      judgeFlags = c.modelFlagOverrides.${judge27b};
      judgeArgs = builtins.concatStringsSep " " c.modelExtraArgs.${judge27b};
      commandBuilder = import ../../modules/mlx/model-server-cmd.nix {
        inherit (pkgs) lib;
        cfg = c;
        mlxModelServerPkg = pkgs.writeShellScriptBin "mlx-model-server" "";
      };
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
    in
    assert
      judgeFlags.cacheMemoryMb == 8192
      || throw "catalog: direct host override (8192) must beat the catalog default, got ${toString judgeFlags.cacheMemoryMb}";
    assert
      judgeFlags.pagedCacheBlockSize == 512 && judgeFlags.maxNumSeqs == 8
      || throw "catalog: 27B resident profile (block 512 / maxNumSeqs 8) not compiled";
    assert
      builtins.match ".*--tool-call-parser.*" judgeCmd == null
      || throw "catalog: official mlx_lm serving args must not carry --tool-call-parser: ${judgeCmd}";
    assert
      c.modelContextWindows.${judge27b} == 131072
      || throw "catalog: Qwen3.8 must compile its 131072-token production window";
    assert
      c.modelFlagOverrides.${judge27b}.maxRequestTokens == 131072
      || throw "catalog: Qwen3.8 must admit its declared 131072-token production window";
    assert
      c.modelContextWindows.${mimo} == 32768
      || throw "catalog: an entry with no declared window must advertise the 32768-token default";
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
      && builtins.match ".*--prompt-cache-size 16.*" judgeCmd != null
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
      && builtins.match ".*--prompt-cache-size 16.*" uncataloguedCmd != null
      && builtins.match ".*--prompt-cache-bytes 8589934592.*" uncataloguedCmd != null
      || throw "catalog: non-catalog official workers must inherit the same bounded serial contract: ${uncataloguedCmd}";
    assert
      builtins.match ".*--max-tokens 8192.*" nullDefaultsCmd != null
      && builtins.match ".*--prompt-cache-bytes 8589934592.*" nullDefaultsCmd != null
      || throw "catalog: nullable legacy settings must retain bounded official mlx_lm defaults: ${nullDefaultsCmd}";
    assert
      c.proxy.logLevel == "info"
      || throw "catalog: production proxy logging must remain prompt-safe INFO";
    assert
      hmConfigCatalog.config.services.aiStack.roleOverrides.judge == judge27b
      || throw "catalog: logical judge role must resolve to the catalog-owned physical model";
    assert
      !(builtins.hasAttr judge27b c.modelTtls)
      || throw "catalog: resident 27B judge must inherit the resident TTL";
    assert
      c.models.${mimo}.ttl == 900
      || throw "catalog: swap ttl must default to 900, got ${toString c.models.${mimo}.ttl}";
    assert
      builtins.match ".*enable_thinking.*false.*" (
        builtins.concatStringsSep " " c.models.${mimo}.extraArgs
      ) != null
      || throw "catalog: MiMo must be served thinking-off";
    assert
      c.models.${ocr}.ttl == 600 && c.modelFlagOverrides.${ocr}.autoUnloadIdleSeconds == 600
      || throw "catalog: ttl tweak (600) must reach both llama-swap ttl and worker idle unload";
    # A catalog concurrencyLimit compiles to the per-model proxy cap, and it
    # matches the role map's concurrency for that model.
    assert
      c.modelConcurrencyLimits.${mimo} == 2 || throw "catalog: mimo-9b must compile concurrencyLimit=2";
    helpers.mkMarker "check-mlx-catalog" "MLX catalog: resident/swap compile, bounded tweak, ttl fan-out, and host-override precedence verified";
}
