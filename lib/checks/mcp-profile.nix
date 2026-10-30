# Shared MCP profile regression tests
{
  pkgs,
  hmConfig,
  hmConfigMcpLaunchPrefix,
  hmConfigGatewayCallers,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  cfg = hmConfig.config.programs.aiMcp;
  expectedGlobalServers = [ ];
  unexpectedGlobalServers = builtins.filter (
    name: !(builtins.elem name expectedGlobalServers)
  ) cfg.enabledServerNames;
  missingGlobalServers = builtins.filter (
    name: !(builtins.elem name cfg.enabledServerNames)
  ) expectedGlobalServers;

  onDemandNames = cfg.onDemandServers;
  # An on-demand server must be absent from the always-on profile AND rendered
  # to a ready-to-attach file. Absent from both would be a silent capability
  # loss, which is the failure this check exists to prevent.
  onDemandLeaked = builtins.filter (name: builtins.elem name cfg.enabledServerNames) onDemandNames;
  onDemandRenderable = builtins.filter (name: cfg.servers ? ${name}) onDemandNames;
  onDemandUnreachable = builtins.filter (
    name: !(hmConfig.config.home.file ? ".claude/mcp-available/${name}.json")
  ) (builtins.filter (name: cfg.onDemandEnabledServers ? ${name}) onDemandRenderable);
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
in
{
  shared-mcp-global-profile =
    assert
      missingGlobalServers == [ ]
      || throw "Shared MCP profile missing global servers: ${builtins.toJSON missingGlobalServers}; actual=${builtins.toJSON cfg.enabledServerNames}";
    assert
      unexpectedGlobalServers == [ ]
      || throw "Shared MCP profile gained unexpected always-on servers: ${builtins.toJSON unexpectedGlobalServers}. Every server costs tokens in EVERY session; add it to programs.aiMcp.onDemandServers unless it is called in nearly all of them.";
    helpers.mkMarker "check-shared-mcp-global-profile" "Shared MCP profile is exactly the ${toString (builtins.length expectedGlobalServers)} expected always-on servers";

  shared-mcp-on-demand-reachable =
    assert
      onDemandLeaked == [ ]
      || throw "On-demand MCP servers leaked into the always-on profile: ${builtins.toJSON onDemandLeaked}";
    assert
      onDemandRenderable == onDemandNames
      || throw "On-demand MCP servers absent from the catalog entirely: ${builtins.toJSON onDemandNames} vs catalog ${builtins.toJSON onDemandRenderable}";
    assert
      onDemandUnreachable == [ ]
      || throw "On-demand MCP servers unreachable — no ~/.claude/mcp-available file: ${builtins.toJSON onDemandUnreachable}";
    helpers.mkMarker "check-shared-mcp-on-demand-reachable" "On-demand MCP servers are out of the always-on profile and still attachable via ~/.claude/mcp-available";

  shared-mcp-renderer-parity =
    assert
      rendererMismatches == [ ]
      || throw "MCP renderer parity mismatch: ${builtins.toJSON rendererMismatches}; shared=${builtins.toJSON cfg.enabledServerNames}; renderers=${builtins.toJSON rendererNames}";
    helpers.mkMarker "check-shared-mcp-renderer-parity" "Shared MCP renderer parity verified for Claude, Codex, Antigravity CLI/IDE, Qwen, and OpenCode";

}
