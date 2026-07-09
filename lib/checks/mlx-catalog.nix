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
      optiqFlags = c.modelFlagOverrides.${optiq};
      optiqArgs = builtins.concatStringsSep " " c.modelExtraArgs.${optiq};
    in
    assert
      optiqFlags.cacheMemoryMb == 8192
      || throw "catalog: direct host override (8192) must beat the catalog default 16384, got ${toString optiqFlags.cacheMemoryMb}";
    assert
      optiqFlags.pagedCacheBlockSize == 256 && optiqFlags.maxNumSeqs == 8
      || throw "catalog: optiq resident profile (block 256 / maxNumSeqs 8) not compiled";
    assert
      builtins.match ".*--tool-call-parser hermes.*--reasoning-parser qwen3.*" optiqArgs != null
      || throw "catalog: optiq family parser args not compiled into modelExtraArgs: ${optiqArgs}";
    assert
      c.modelFlagOverrides.${coder}.maxRequestTokens == 32768
      || throw "catalog: coder resident maxRequestTokens 32768 not compiled";
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
    helpers.mkMarker "check-mlx-catalog" "MLX catalog: resident/swap compile, bounded tweak, ttl fan-out, and host-override precedence verified";
}
