# OpenCode module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.opencode;
  homeDir = hmConfig.config.home.homeDirectory;
  settingsFile = hmConfig.config.home.file."${cfg.configDir}/opencode.json".source;
  localRouterAlias = "small";
  routerAliases = import ../../modules/litellm-local/aliases.nix;
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
      "sandbox"
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
      {
        name = "opencode.sandbox.enable";
        actual = cfg.sandbox.enable;
        expected = pkgs.stdenv.hostPlatform.isDarwin;
      }
      {
        name = "opencode.sandbox.workRoot";
        actual = cfg.sandbox.workRoot;
        expected = "${homeDir}/opencode-work";
      }
    ];
  };

  opencode-router-local-agent =
    assert builtins.elem localRouterAlias routerAliases;
    pkgs.runCommand "check-opencode-router-local-agent"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq -e --arg alias "${localRouterAlias}" '
          .provider.router.npm == "@ai-sdk/openai-compatible" and
          .provider.router.name == "router" and
          .provider.router.options == {
            baseURL: "{env:AGENT_ROUTER_BASE_URL}",
            apiKey: "{env:AGENT_ROUTER_LOCAL_KEY}"
          } and
          .provider.router.models[$alias].name == $alias and
          .agent.local.mode == "subagent" and
          .agent.local.model == ("router/" + $alias)
        ' ${settingsFile} >/dev/null
        touch $out
      '';
}
