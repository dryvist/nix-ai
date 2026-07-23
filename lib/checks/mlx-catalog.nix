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
      judge27b = "mlx-community/Qwen3.6-27B-mxfp4";
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
      builtins.match ".*--decode-concurrency 1.*--prompt-concurrency 1.*" optiqCmd != null
      && builtins.match ".*--tool-call-parser.*" optiqCmd == null
      || throw "catalog: official mlx_lm serial-serving args not compiled cleanly: ${optiqCmd}";
    assert
      c.modelFlagOverrides.${coder}.maxRequestTokens == 32768
      || throw "catalog: coder resident maxRequestTokens 32768 not compiled";
    assert
      c.modelServerBackend == "mlx-lm"
      || throw "catalog: the goal judge must use the selected mlx_lm.server deployment path";
    assert
      c.enabledBackends == [ "mlx-lm" ]
      || throw "catalog: official mlx-lm must be the only enabled backend; vllm-mlx must remain preserved but disabled";
    assert
      !hmConfigCatalog.config.launchd.agents.mlx-model-server-watchdog.enable
      || throw "catalog: the vllm-specific watchdog must stay disabled for mlx-lm";
    assert
      c.modelConcurrencyLimits.${judge27b} == 1
      && builtins.match ".*enable_thinking.*false.*" judgeArgs != null
      || throw "catalog: 27B judge must use bounded single-concurrency text serving";
    assert
      builtins.match ".*mlx-model-server --model mlx-community/Qwen3.6-27B-mxfp4.*" judgeCmd != null
      && builtins.match ".*--log-level INFO.*" judgeCmd != null
      && builtins.match ".*--max-tokens 8192.*" judgeCmd != null
      && builtins.match ".*--decode-concurrency 1.*" judgeCmd != null
      && builtins.match ".*--prompt-concurrency 1.*" judgeCmd != null
      && builtins.match ".*--prompt-cache-size 1.*" judgeCmd != null
      && builtins.match ".*--prompt-cache-bytes 8589934592.*" judgeCmd != null
      && builtins.match ".*vllm-mlx.*" judgeCmd == null
      && builtins.match ".*--gpu-memory-utilization.*" judgeCmd == null
      || throw "catalog: 27B judge command must use only the bounded official mlx_lm serving contract: ${judgeCmd}";
    assert
      builtins.match ".*--log-level INFO.*" uncataloguedCmd != null
      && builtins.match ".*--max-tokens 8192.*" uncataloguedCmd != null
      && builtins.match ".*--decode-concurrency 1.*" uncataloguedCmd != null
      && builtins.match ".*--prompt-concurrency 1.*" uncataloguedCmd != null
      && builtins.match ".*--prompt-cache-size 1.*" uncataloguedCmd != null
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
