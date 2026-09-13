# Regression for the responseHeaderTimeout ordering assertion
# (modules/mlx/assertions.nix) and the per-model override option
# (modules/mlx/options-proxy.nix).
#
# Same technique as ./mlx-mtp-reachable.nix: read config.assertions off a
# REAL evaluation rather than hand-building a cfg attrset, since the
# assertion itself only exists inside the module system's evalModules pass.
#
# Two configs:
#   ladderGood -- a per-model override that stays under both ladder rungs.
#                 The ordering assertion must hold, and the option must
#                 carry the override value for that one model while the
#                 global default is unaffected.
#   ladderBad  -- a per-model override at 2400s, equal to the router's own
#                 timeout. The ordering assertion must FAIL: an override at
#                 or above either rung defeats that rung's own bound, and a
#                 check that only ever evaluates a passing config can't tell
#                 a live assertion from one that always reports true.
{
  pkgs,
  mkHmConfig,
}:
let
  target = "mlx-community/Qwen3.8-27B-4bit";
  overrideValue = 500;

  baseCfg = {
    judge.model = "mlx-community/test-judge-model";
    defaultModelKey = "qwen38-27b";
    catalog.qwen38-27b.class = "resident";
  };

  ladderGoodHm = mkHmConfig [
    {
      programs.mlx = baseCfg // {
        modelResponseHeaderTimeouts.${target} = overrideValue;
      };
    }
  ];

  ladderBadHm = mkHmConfig [
    {
      programs.mlx = baseCfg // {
        modelResponseHeaderTimeouts.${target} = 2400;
      };
    }
  ];

  # Reading config.assertions on a config with a FAILING assertion throws
  # immediately -- the module system's own assertion enforcement runs before
  # a caller ever gets to inspect an individual assertion's `.assertion`
  # field. tryEval is therefore the only way to observe "this config's
  # assertions reject it" without also throwing the check itself. Same
  # technique as ./mlx-catalog-roles.nix's uniquenessOf check and
  # ./litellm-local-negative.nix's routerEntryEvaluates.
  goodEval = builtins.tryEval (
    builtins.deepSeq ladderGoodHm.config.assertions ladderGoodHm.config.assertions
  );
  badEval = builtins.tryEval (
    builtins.deepSeq ladderBadHm.config.assertions ladderBadHm.config.assertions
  );

  goodCfg = ladderGoodHm.config.programs.mlx;
in
{
  mlx-response-header-timeout-ladder =
    assert
      goodEval.success
      || throw "mlx response-header-timeout ladder: a config with a safe per-model override must evaluate cleanly (every assertion holds), but evaluation failed";
    assert
      (goodCfg.modelResponseHeaderTimeouts.${target} or null) == overrideValue
      || throw "mlx response-header-timeout ladder: modelResponseHeaderTimeouts.${target} did not carry the configured override (${toString overrideValue})";
    assert
      goodCfg.proxy.responseHeaderTimeout != overrideValue
      || throw "mlx response-header-timeout ladder: fixture assumption broken -- the per-model override must differ from the global default to prove per-model scoping, but they are equal";
    assert
      !badEval.success
      || throw "mlx response-header-timeout ladder: an override at the router's own timeout (2400s) must fail evaluation (the ordering assertion rejects it); it evaluated cleanly instead, so the assertion no longer catches this class of misconfiguration";
    pkgs.runCommand "check-mlx-response-header-timeout-ladder" { } "touch $out";
}
