# Regressions for native MCP definitions that merge after the shared renderer.
{
  pkgs,
  mkHmConfig,
  rendererNames,
  ...
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  facadeGateway = "https://gateway.example.invalid";
  facadeNames = [ "agent-facade" ];
  injectedRemoteMcp = {
    type = "remote";
    url = "https://extra.example.invalid/mcp";
  };
  nativeMcpMaps = import ./mcp-facade-native-maps.nix;
  nativeMcpMapNames = hm: lib.mapAttrs (_: servers: builtins.attrNames servers) (nativeMcpMaps hm);
  hmConfigSelectorBaseline = mkHmConfig [
    {
      programs.opencode.enable = true;
      programs.aiMcp.gatewayBaseUrl = facadeGateway;
    }
  ];
  hmConfigOpenCodeExtra = mkHmConfig [
    {
      programs = {
        opencode = {
          enable = true;
          extraSettings.mcp.injected = injectedRemoteMcp;
        };
        aiMcp.gatewayBaseUrl = facadeGateway;
      };
    }
  ];
  hmConfigOpenCodeOnlyExtra = mkHmConfig [
    {
      programs = {
        opencode = {
          enable = true;
          extraSettings.mcp.injected = injectedRemoteMcp;
        };
        aiMcp = {
          gatewayBaseUrl = facadeGateway;
          facadeCanaryClients.opencode = true;
        };
      };
    }
  ];
  hmConfigQwenExtra = mkHmConfig [
    {
      programs = {
        opencode.enable = true;
        qwen-code.extraSettings.mcpServers.injected.httpUrl = injectedRemoteMcp.url;
        aiMcp.gatewayBaseUrl = facadeGateway;
      };
    }
  ];
  hmConfigQwenOnlyExtra = mkHmConfig [
    {
      programs = {
        opencode.enable = true;
        qwen-code.extraSettings.mcpServers.injected.httpUrl = injectedRemoteMcp.url;
        aiMcp = {
          gatewayBaseUrl = facadeGateway;
          facadeCanaryClients.qwen-code = true;
        };
      };
    }
  ];
  injectedClaudeMcp = {
    type = "http";
    inherit (injectedRemoteMcp) url;
  };
  hmConfigClaudeExtra = mkHmConfig [
    {
      programs = {
        opencode.enable = true;
        claude.mcpServers.injected = injectedClaudeMcp;
        aiMcp.gatewayBaseUrl = facadeGateway;
      };
    }
  ];
  hmConfigClaudeOnlyExtra = mkHmConfig [
    {
      programs = {
        opencode.enable = true;
        claude.mcpServers.injected = injectedClaudeMcp;
        aiMcp = {
          gatewayBaseUrl = facadeGateway;
          facadeCanaryClients.claude = true;
        };
      };
    }
  ];
  injectedExtensionMcp = {
    type = "http";
    inherit (injectedRemoteMcp) url;
  };
  mkExtensionConfig = selected: {
    programs = {
      antigravity-cli = {
        enable = true;
        extensions.fixture = {
          description = "Synthetic selector merge fixture";
          mcpServers.injected = injectedExtensionMcp;
        };
      };
      opencode.enable = true;
      aiMcp = {
        gatewayBaseUrl = facadeGateway;
        facadeCanaryClients.antigravity-cli = selected;
      };
    };
  };
  hmConfigAntigravityCliExtra = mkHmConfig [ (mkExtensionConfig false) ];
  hmConfigAntigravityCliOnlyExtra = mkHmConfig [ (mkExtensionConfig true) ];
  hmConfigClaudeExcluded = mkHmConfig [
    {
      programs = {
        opencode.enable = true;
        claude.excludedMcpServers = [ "zammad" ];
        aiMcp.gatewayBaseUrl = facadeGateway;
      };
    }
  ];
  hmConfigCodexOnlyClaudeExcluded = mkHmConfig [
    {
      programs = {
        opencode.enable = true;
        aiMcp = {
          gatewayBaseUrl = facadeGateway;
          facadeCanaryClients.codex = true;
        };
        claude.excludedMcpServers = [ "zammad" ];
      };
    }
  ];
  unselectedRendererMismatches =
    hm: selected:
    builtins.filter (
      name:
      name != selected && (nativeMcpMaps hm).${name} != (nativeMcpMaps hmConfigSelectorBaseline).${name}
    ) (builtins.attrNames rendererNames);
  extensionManifest =
    hm:
    builtins.fromJSON
      hm.config.home.file.".gemini/antigravity-cli/extensions/fixture/antigravity-extension.json".text;
in
{
  facade-canary-final-native-merges =
    assert
      (nativeMcpMaps hmConfigOpenCodeExtra).opencode.injected == injectedRemoteMcp
      && (nativeMcpMapNames hmConfigOpenCodeOnlyExtra).opencode == facadeNames
      && unselectedRendererMismatches hmConfigOpenCodeOnlyExtra "opencode" == [ ]
      || throw "OpenCode final recursive merge can add an MCP server after selection";
    assert
      (nativeMcpMaps hmConfigQwenExtra)."qwen-code".injected.httpUrl == injectedRemoteMcp.url
      && (nativeMcpMapNames hmConfigQwenOnlyExtra)."qwen-code" == facadeNames
      && unselectedRendererMismatches hmConfigQwenOnlyExtra "qwen-code" == [ ]
      || throw "Qwen final settings merge can add an MCP server after selection";
    assert
      (nativeMcpMaps hmConfigClaudeExtra).claude.injected.url == injectedClaudeMcp.url
      && (nativeMcpMapNames hmConfigClaudeOnlyExtra).claude == facadeNames
      && unselectedRendererMismatches hmConfigClaudeOnlyExtra "claude" == [ ]
      || throw "Claude downstream attrs merge can add an MCP server after selection";
    assert
      (nativeMcpMapNames hmConfigAntigravityCliOnlyExtra)."antigravity-cli" == facadeNames
      && unselectedRendererMismatches hmConfigAntigravityCliExtra "antigravity-cli" == [ ]
      && (extensionManifest hmConfigAntigravityCliExtra).mcpServers.injected == injectedExtensionMcp
      && (extensionManifest hmConfigAntigravityCliOnlyExtra).mcpServers == { }
      || throw "Antigravity CLI extension MCP merges bypass its selected singleton facade set";
    assert
      hmConfigClaudeExcluded.config.programs.claude.settings.enabledMcpjsonServers
      == builtins.attrNames hmConfigClaudeExcluded.config.programs.aiMcp.onDemandEnabledServers
      && !(builtins.elem "zammad" hmConfigClaudeExcluded.config.programs.claude.mcpServerNames)
      && !(hmConfigClaudeExcluded.config.home.file ? ".claude/mcp-available/zammad.json")
      &&
        hmConfigCodexOnlyClaudeExcluded.config.programs.claude.settings.enabledMcpjsonServers
        == builtins.attrNames hmConfigCodexOnlyClaudeExcluded.config.programs.aiMcp.onDemandEnabledServers
      && !(hmConfigCodexOnlyClaudeExcluded.config.home.file ? ".claude/mcp-available/zammad.json")
      || throw "unselected Claude approval names changed under zammad exclusion or Codex-only selection";
    helpers.mkMarker "check-facade-canary-final-native-merges" "Final native settings and extension merges cannot add MCP servers after per-client selection; unselected definitions and Claude approvals remain unchanged";
}
