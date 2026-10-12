# Qwen Code module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.qwen-code;
  homeDir = hmConfig.config.home.homeDirectory;
in
{
  # Verify all expected Qwen Code option paths exist.
  qwen-code-options-regression = helpers.mkOptionsRegression {
    label = "Qwen Code";
    checkName = "check-qwen-code-options-regression";
    inherit cfg;
    expectedOptions = [
      "contextFileNames"
      "enable"
      "excludedMcpServers"
      "extraSettings"
      "installVia"
      "mcpServerNames"
      "model"
      "sandbox"
    ];
  };

  # Verify evaluated config values match expected defaults.
  qwen-code-defaults-regression = helpers.mkDefaultsRegression {
    label = "Qwen Code";
    checkName = "check-qwen-code-defaults-regression";
    checks = [
      {
        name = "qwen-code.enable";
        actual = cfg.enable;
        expected = true;
      }
      {
        name = "qwen-code.model";
        actual = cfg.model;
        expected = "coding";
      }
      {
        name = "qwen-code.contextFileNames";
        actual = cfg.contextFileNames;
        expected = [ "AGENTS.md" ];
      }
      {
        name = "qwen-code.sandbox.enable";
        actual = cfg.sandbox.enable;
        expected = pkgs.stdenv.hostPlatform.isDarwin;
      }
      {
        name = "qwen-code.sandbox.workRoot";
        actual = cfg.sandbox.workRoot;
        expected = "${homeDir}/qwen-code-work";
      }
    ];
  };
}
