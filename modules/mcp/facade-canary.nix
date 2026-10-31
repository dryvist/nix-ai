# Facade canary: a consumer whose entire MCP surface is agent-facade.
#
# programs.aiMcp.facadeCanary = true makes sourceServers hold agent-facade alone,
# forced on; modules/mcp/default.nix computes every shared set from it. This
# module declares the option, fails evaluation when a canary enables any other
# server, and empties the agent-skills group attachments, which name on-demand
# servers.
{
  config,
  lib,
  options,
  pkgs,
  ...
}:

let
  cfg = config.programs.aiMcp;
  facade = "agent-facade";
  catalog = import ./catalog.nix {
    inherit pkgs;
    inherit (cfg) gatewayBaseUrl;
  };
  enabled = name: !(cfg.servers.${name}.disabled or false);
  # Enabled servers that are not in the catalog (extraOnDemandMcpServers merges
  # into servers), and catalog entries the consumer switched on.
  violations =
    builtins.filter (name: !(catalog ? ${name}) && enabled name) (builtins.attrNames cfg.servers)
    ++ builtins.filter (name: name != facade && enabled name && (catalog.${name}.disabled or false)) (
      builtins.attrNames catalog
    );
in
{
  options.programs.aiMcp = {
    facadeCanary = lib.mkEnableOption "the facade canary, whose entire MCP surface is agent-facade";

    sourceServers = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
      description = "Servers the shared MCP sets are computed from: all of servers, or agent-facade alone on a canary.";
    };
  };

  config = lib.mkMerge [
    {
      programs.aiMcp.sourceServers =
        if cfg.facadeCanary then
          {
            agent-facade = cfg.servers.agent-facade // {
              disabled = false;
            };
          }
        else
          cfg.servers;
    }
    (lib.mkIf cfg.facadeCanary (
      {
        assertions = [
          {
            assertion = violations == [ ];
            message = "facadeCanary: these servers are enabled beside agent-facade: ${builtins.toJSON violations}";
          }
          {
            assertion = cfg.gatewayBaseUrl != null;
            message = "facadeCanary: programs.aiMcp.gatewayBaseUrl must be set; agent-facade is a gateway route";
          }
        ];
      }
      # Module sets that import module.nix without agent-skills must still evaluate.
      // lib.optionalAttrs (options.programs ? agentSkills) {
        programs.agentSkills.groupMcpServers = lib.mkForce { };
      }
    ))
  ];
}
