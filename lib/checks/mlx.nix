# MLX option and model-server command regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  mlxCfg = hmConfig.config.programs.mlx;
in
{
  # Verify all expected MLX option paths exist.
  # Flat structure — no nested backend settings.
  mlx-options-regression = helpers.mkOptionsRegression {
    label = "MLX";
    checkName = "check-mlx-options-regression";
    cfg = mlxCfg;
    expectedOptions = [
      "alwaysAvailableModels"
      "autoUnloadIdleSeconds"
      "bufferCacheLimitGb"
      "cacheMemoryMb"
      "defaultModel"
      "enable"
      "enablePrefixCaching"
      "host"
      "huggingFaceHome"
      "maxTokens"
      "maxNumSeqs"
      "memoryHardLimitGb"
      "models"
      "pagedKvCache"
      "port"
      "prefillBatchSize"
      "proxy"
      "serverLogLevel"
      "singleModel"
    ];
  };

  # Verify MLX evaluated config values match expected defaults.
  mlx-defaults-regression = helpers.mkDefaultsRegression {
    label = "MLX";
    checkName = "check-mlx-defaults-regression";
    # Data lives in ./mlx-defaults-data.nix -- this file reached the 12KB
    # file-size ceiling, so the expectations were split out by responsibility:
    # that file is WHAT each default should be, this one keeps the checks that
    # exercise behaviour (rendered command, LaunchAgent, negative cases).
    checks = import ./mlx-defaults-data.nix { inherit mlxCfg hmConfig; };
  };

  # The backend-neutral serverLogLevel must reach the selected server's native
  # command. This catches a backend switch silently falling back to its own
  # logging default while the evaluated option still reports "debug".
  mlx-server-log-level =
    let
      testServerPkg = pkgs.writeShellScriptBin "mlx-lm-server-test" "exit 0";
      cmd =
        (import ../../modules/mlx/model-server-cmd.nix {
          inherit (pkgs) lib;
          cfg = mlxCfg;
          mlxModelServerPkg = testServerPkg;
        }).mkModelCmd
          mlxCfg.defaultModel;
    in
    assert
      builtins.match ".*--log-level INFO.*" cmd != null
      || throw "programs.mlx.serverLogLevel=info did not render --log-level INFO for mlx_lm";
    helpers.mkMarker "check-mlx-server-log-level" "MLX server log level: INFO reaches the official mlx_lm command";

  # python-overlay.nix's cpTag already carries the "cp" prefix ("3.14" ->
  # "cp314"), so prefixing it again renders "cpcp314" — a tag no wheel has. It
  # only surfaced inside a throw, on the unhappy path a version bump lands on,
  # pointing whoever hit it at a PyPI filename that does not exist.
  #
  # This reads the source rather than the rendered message because Nix cannot
  # catch a throw's text: builtins.tryEval reports only success/failure. The
  # literal is what the bug looks like, so matching it is the cheapest thing
  # that fails if the double prefix comes back.
  mlx-overlay-wheel-tag =
    let
      overlay = builtins.readFile ../../modules/mlx/python-overlay.nix;
    in
    assert
      !(pkgs.lib.hasInfix "cp\${cpTag}" overlay)
      || throw "mlx: modules/mlx/python-overlay.nix prefixes \"cp\" to cpTag, which already begins with it — the message renders cpcp314 instead of cp314. Interpolate cpTag alone.";
    helpers.mkMarker "check-mlx-overlay-wheel-tag" "MLX overlay: the wheel interpreter tag is interpolated once, never double-prefixed";
}
