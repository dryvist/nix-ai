# Shared MCP profile regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.aiMcp;
  expectedGlobalServers = [
    "codex"
    "fabric"
    "huggingface"
    "splunk"
    "time"
  ]
  ++ pkgs.lib.optional pkgs.stdenv.isDarwin "apple-events";
  missingGlobalServers = builtins.filter (
    name: !(builtins.elem name cfg.enabledServerNames)
  ) expectedGlobalServers;
  rendererNames = {
    claude = builtins.attrNames hmConfig.config.programs.claude.mcpServers;
    codex = hmConfig.config.programs.codex.mcpServerNames;
    antigravity-cli = hmConfig.config.programs.antigravity-cli.mcpServerNames;
    antigravity-ide = hmConfig.config.programs.antigravity-ide.mcpServerNames;
    qwen-code = hmConfig.config.programs.qwen-code.mcpServerNames;
    opencode = hmConfig.config.programs.opencode.mcpServerNames;
  };
  rendererMismatches = builtins.filter (name: rendererNames.${name} != cfg.enabledServerNames) (
    builtins.attrNames rendererNames
  );
  codexLaunchContracts = {
    splunk = {
      env_vars = [
        "BAO_ADDR"
        "AI_READONLY_ROLE_ID"
        "AI_READONLY_SECRET_ID"
        "SPLUNK_MCP_OPENBAO_PATH"
      ];
      startup_timeout_sec = 300;
      tool_timeout_sec = 300;
    };
    vikunja = {
      env_vars = [
        "AI_DOPPLER_PROJECT"
        "AI_DOPPLER_CONFIG"
      ];
      startup_timeout_sec = 300;
      tool_timeout_sec = 300;
    };
    zammad = {
      env_vars = [
        "AI_DOPPLER_PROJECT"
        "AI_DOPPLER_CONFIG"
      ];
      startup_timeout_sec = 300;
      tool_timeout_sec = 300;
    };
  };
  codexLaunchContractMismatches = builtins.filter (
    name:
    builtins.any (key: cfg.servers.${name}.${key} != codexLaunchContracts.${name}.${key}) [
      "env_vars"
      "startup_timeout_sec"
      "tool_timeout_sec"
    ]
  ) (builtins.attrNames codexLaunchContracts);
in
{
  shared-mcp-global-profile =
    assert
      missingGlobalServers == [ ]
      || throw "Shared MCP profile missing global servers: ${builtins.toJSON missingGlobalServers}; actual=${builtins.toJSON cfg.enabledServerNames}";
    helpers.mkMarker "check-shared-mcp-global-profile" "Shared MCP profile includes ${toString (builtins.length expectedGlobalServers)} expected global servers";

  shared-mcp-renderer-parity =
    assert
      rendererMismatches == [ ]
      || throw "MCP renderer parity mismatch: ${builtins.toJSON rendererMismatches}; shared=${builtins.toJSON cfg.enabledServerNames}; renderers=${builtins.toJSON rendererNames}";
    helpers.mkMarker "check-shared-mcp-renderer-parity" "Shared MCP renderer parity verified for Claude, Codex, Antigravity CLI/IDE, Qwen, and OpenCode";

  splunk-mcp-canonical-launcher =
    assert
      cfg.servers.splunk.command == "splunk-mcp-connect" && cfg.servers.splunk.args == [ ]
      || throw "Splunk MCP must launch directly through splunk-mcp-connect: ${builtins.toJSON cfg.servers.splunk}";
    helpers.mkMarker "check-splunk-mcp-canonical-launcher" "Splunk MCP uses the OpenBao launcher without Doppler wiring";

  codex-mcp-launch-contract =
    assert
      codexLaunchContractMismatches == [ ]
      || throw "Codex MCP launch contract mismatch: ${builtins.toJSON codexLaunchContractMismatches}; actual=${
        builtins.toJSON (builtins.map (name: cfg.servers.${name}) (builtins.attrNames codexLaunchContracts))
      }";
    helpers.mkMarker "check-codex-mcp-launch-contract" "Codex MCP servers have explicit environment allowlists and 300-second startup/tool timeouts";

  splunk-mcp-openbao-wrapper =
    pkgs.runCommand "check-splunk-mcp-openbao-wrapper"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        ${pkgs.bash}/bin/bash ${../../modules/mcp/tests/splunk-mcp-connect.sh} \
          ${../../modules/mcp/scripts/splunk-mcp-connect.sh}
        touch $out
      '';
}
