# Catalog compile regression tests (programs.mlx.catalog -> per-model surfaces)
{ pkgs, hmConfigCatalog }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  # Catalog compile regression (programs.mlx.catalog -> per-model surfaces).
  # Uses hmConfigCatalog (lib/checks-fixtures.nix): 27B resident, MiMo swap,
  # plus a direct host override on the 27B's
  # cacheMemoryMb that must beat the catalog's mkDefault.
  mlx-catalog =
    let
      c = hmConfigCatalog.config.programs.mlx;
      mimo = "mlx-community/MiMo-V2.6-Distill-Qwen-9B-OptiQ-4bit";
      ocr = "mlx-community/Unlimited-OCR-bf16";
      judge27b = "mlx-community/Qwen3.8-27B-4bit";
      modelCatalog = import ../../modules/mlx/model-catalog.nix;
      mimoModel = modelCatalog.${mimo};
      mimoProfile = mimoModel.profiles.mlx;
      mimoSwap = mimoProfile.swap;
      judgeModel = modelCatalog.${judge27b};
      judgeProfile = judgeModel.profiles.mlx;
      judgeMaxOutput = judgeProfile.max_output_tokens or judgeModel.max_output_tokens;
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
    in
    assert
      judgeFlags.cacheMemoryMb == 8192
      || throw "catalog: direct host override (8192) must beat the catalog default, got ${toString judgeFlags.cacheMemoryMb}";
    assert
      judgeFlags.pagedCacheBlockSize == judgeProfile.paged_cache_block_size
      && judgeFlags.maxNumSeqs == judgeProfile.max_num_sequences
      || throw "catalog: Qwen3.8 resident cache settings disagree with the shared model profile";
    assert
      builtins.match ".*--tool-call-parser.*" judgeCmd == null
      || throw "catalog: official mlx_lm serving args must not carry --tool-call-parser: ${judgeCmd}";
    assert
      c.modelContextWindows.${judge27b} == judgeProfile.context_window
      || throw "catalog: Qwen3.8 context window disagrees with the shared model profile";
    assert
      c.modelFlagOverrides.${judge27b}.maxRequestTokens == judgeProfile.context_window
      || throw "catalog: Qwen3.8 request cap disagrees with the shared model profile";
    assert
      c.modelContextWindows.${mimo} == mimoProfile.context_window
      || throw "catalog: MiMo context window disagrees with the shared MLX profile";
    # Worker concurrency and proxy admission are separate: the Qwen worker
    # stays serial while the proxy admits its active slot plus bounded waiters.
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
      c.modelConcurrencyLimits.${judge27b} == 1
      && c.modelAdmissionLimits.${judge27b} == judgeProfile.queue_size + 1
      && builtins.match ".*reasoning_effort.*(low|medium).*" judgeArgs != null
      || throw "catalog: the 27B entry must keep worker concurrency at 1, admit queue capacity plus the active request, and pin reasoning_effort to low or medium";
    # MiMo admission: worker concurrency plus the bounded queue (as for the 27B entry).
    assert
      c.modelConcurrencyLimits.${mimo} == mimoProfile.max_parallel_requests
      && c.modelAdmissionLimits.${mimo} == c.modelConcurrencyLimits.${mimo} + mimoProfile.queue_size
      && mimoProfile.max_parallel_requests != mimoModel.max_parallel_requests
      && c.modelFlagOverrides.${mimo}.maxNumSeqs == mimoSwap.max_num_sequences
      && c.modelFlagOverrides.${mimo}.maxRequestTokens == mimoSwap.max_request_tokens
      && c.modelFlagOverrides.${mimo}.autoUnloadIdleSeconds == mimoSwap.auto_unload_idle_seconds
      && c.modelFlagOverrides.${mimo}.cacheMemoryMb == mimoSwap.cache_memory_mb
      || throw "catalog: MiMo backend and swap projections disagree with the shared model profile";
    assert
      builtins.match ".*mlx-model-server --model mlx-community/Qwen3.8-27B-4bit.*" judgeCmd != null
      && builtins.match ".*--log-level INFO.*" judgeCmd != null
      && builtins.match ".*--max-tokens ${toString judgeMaxOutput}.*" judgeCmd != null
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
      hmConfigCatalog.config.services.aiStack.roleOverrides.judge == judge27b
      || throw "catalog: logical judge role must resolve to the catalog-owned physical model";
    assert
      c.staticResidentContracts.${judge27b}.queueSize == judgeProfile.queue_size
      || throw "catalog: Qwen3.8 resident queue disagrees with the shared model profile";
    assert
      c.modelBackends.${ocr} == "mlx-vlm"
      || throw "catalog: the role-map OCR entry remains declared on its VLM backend";
    helpers.mkMarker "check-mlx-catalog" "MLX catalog: resident command, role-map OCR metadata, context and host-override precedence verified";
}
