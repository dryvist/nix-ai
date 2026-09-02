# Shared MCP profile regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.aiMcp;
  # The nix-managed always-on profile is deliberately EMPTY. zammad and
  # apple-events left first (~29k tokens between them); codex, fabric, grep and
  # time followed on measured usage — 149/124/117/54 calls across 1,651 local
  # transcripts, costing 5,474 tokens of every session between them. A session
  # calling none of them, which is most sessions, paid that for nothing.
  #
  # Asserted as an EXACT SET, not a floor. An empty floor would be vacuously
  # true and would prove nothing; equality fails in both directions, so a
  # server silently re-added to the always-on profile fails the build just as a
  # missing one would. shared-mcp-on-demand-reachable proves everything moved
  # out is still attachable, which is what makes each move a scoping change
  # rather than a capability loss.
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
    cursor = hmConfig.config.programs.cursor.mcpServerNames;
  };
  rendererMismatches = builtins.filter (name: rendererNames.${name} != cfg.enabledServerNames) (
    builtins.attrNames rendererNames
  );
  codexLaunchContracts = {
    time = { };
    huggingface = { };
    fabric = { };
    apple-events = { };
    splunk = {
      env_vars = [
        "BAO_ADDR"
        "AI_READONLY_ROLE_ID"
        "AI_READONLY_SECRET_ID"
        "SPLUNK_MCP_OPENBAO_PATH"
      ];
    };
    vikunja = {
      env_vars = [
        "AI_DOPPLER_PROJECT"
        "AI_DOPPLER_CONFIG"
      ];
    };
    zammad = {
      env_vars = [
        "AI_DOPPLER_PROJECT"
        "AI_DOPPLER_CONFIG"
      ];
    };
  };
  codexLaunchContractMismatches = builtins.filter (
    name:
    let
      expected = codexLaunchContracts.${name};
      actual = cfg.servers.${name};
    in
    actual.startup_timeout_sec != 300
    || actual.tool_timeout_sec != 300
    || (expected ? env_vars && actual.env_vars != expected.env_vars)
  ) (builtins.attrNames codexLaunchContracts);
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
    helpers.mkMarker "check-shared-mcp-renderer-parity" "Shared MCP renderer parity verified for Claude, Codex, Antigravity CLI/IDE, Qwen, OpenCode, and Cursor";

  splunk-mcp-canonical-launcher =
    assert
      cfg.servers.splunk.command == "splunk-mcp-connect" && cfg.servers.splunk.args == [ ]
      || throw "Splunk MCP must launch directly through splunk-mcp-connect: ${builtins.toJSON cfg.servers.splunk}";
    helpers.mkMarker "check-splunk-mcp-canonical-launcher" "Splunk MCP uses the OpenBao launcher without Doppler wiring";

  codex-mcp-launch-contract =
    assert
      codexLaunchContractMismatches == [ ]
      || throw "Codex MCP launch contract mismatch: ${builtins.toJSON codexLaunchContractMismatches}";
    helpers.mkMarker "check-codex-mcp-launch-contract" "Codex MCP servers have scoped environment forwarding and 300-second startup/tool timeouts";

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
