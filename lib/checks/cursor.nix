# Cursor CLI module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.cursor;
in
{
  # Verify all expected Cursor option paths exist.
  cursor-options-regression = helpers.mkOptionsRegression {
    label = "Cursor";
    checkName = "check-cursor-options-regression";
    inherit cfg;
    expectedOptions = [
      "approvalMode"
      "enable"
      "excludedMcpServers"
      "extraSettings"
      "mcpServerNames"
      "vimMode"
    ];
  };

  # Verify evaluated config values match expected defaults.
  cursor-defaults-regression = helpers.mkDefaultsRegression {
    label = "Cursor";
    checkName = "check-cursor-defaults-regression";
    checks = [
      {
        name = "cursor.enable";
        actual = cfg.enable;
        expected = true;
      }
      {
        name = "cursor.vimMode";
        actual = cfg.vimMode;
        expected = false;
      }
      {
        name = "cursor.approvalMode";
        actual = cfg.approvalMode;
        expected = "allowlist";
      }
    ];
  };

  # Verify the wrapper-required binary symlinks and CLI config activation are
  # wired when the module is enabled.
  cursor-binaries-regression = helpers.mkOptionsRegression {
    label = "Cursor binary symlinks";
    checkName = "check-cursor-binaries-regression";
    cfg = hmConfig.config.home.file;
    expectedOptions = [
      ".local/bin/agent"
      ".local/bin/cursor-agent"
    ];
  };

  cursor-activation-regression = helpers.mkDefaultsRegression {
    label = "Cursor activation";
    checkName = "check-cursor-activation-regression";
    checks = [
      {
        name = "cursor.configMerge activation present";
        actual = hmConfig.config.home.activation ? cursorConfigMerge;
        expected = true;
      }
    ];
  };
}
