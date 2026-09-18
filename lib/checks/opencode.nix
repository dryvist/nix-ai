# OpenCode module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.opencode;
in
{
  # Verify all expected OpenCode option paths exist.
  opencode-options-regression = helpers.mkOptionsRegression {
    label = "OpenCode";
    checkName = "check-opencode-options-regression";
    inherit cfg;
    expectedOptions = [
      "commandDirs"
      "configDir"
      "enable"
      "excludedMcpServers"
      "extraModels"
      "extraSettings"
      "lspEnabled"
      "mcpServerNames"
      "otelPluginEntries"
      "package"
    ];
  };

  # Verify evaluated config values match expected defaults.
  opencode-defaults-regression = helpers.mkDefaultsRegression {
    label = "OpenCode";
    checkName = "check-opencode-defaults-regression";
    checks = [
      {
        name = "opencode.enable";
        actual = cfg.enable;
        expected = true;
      }
      {
        # LSP integration on: every built-in server activates when its binary
        # is on PATH (ai-tools.nix language servers). Paired with the env var
        # below so OpenCode never fetches a server out-of-band instead.
        name = "opencode.lspEnabled";
        actual = cfg.lspEnabled;
        expected = true;
      }
      {
        name = "home.sessionVariables.OPENCODE_DISABLE_LSP_DOWNLOAD";
        actual = hmConfig.config.home.sessionVariables.OPENCODE_DISABLE_LSP_DOWNLOAD or null;
        expected = "true";
      }
    ];
  };
}
