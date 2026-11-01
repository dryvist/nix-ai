# Facade canary selectors choose which MCP client renders the canonical facade
# as its complete effective MCP set. The legacy facadeCanary switch remains a
# dominant all-client selector.
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
  clients = [
    "claude"
    "codex"
    "antigravity-cli"
    "antigravity-ide"
    "qwen-code"
    "opencode"
  ];
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
  selectedClients = builtins.filter (name: cfg.facadeCanaryClients.${name}) clients;
  anyCanary = cfg.facadeCanary || selectedClients != [ ];
  facadeServer =
    if cfg.facadeCanary then
      cfg.servers.${facade}
      // {
        disabled = false;
      }
    else
      cfg.servers.${facade}
      // catalog.${facade}
      // {
        disabled = false;
      };
in
{
  options.programs.aiMcp = {
    facadeCanary = lib.mkEnableOption ''
      the legacy facade canary, whose entire MCP surface is agent-facade for every client
      (dominates facadeCanaryClients)
    '';

    facadeCanaryClients = lib.mkOption {
      type = lib.types.submodule {
        options = {
          claude = lib.mkEnableOption "the whole-set agent-facade selector for Claude Code";
          codex = lib.mkEnableOption "the whole-set agent-facade selector for Codex";
          antigravity-cli = lib.mkEnableOption "the whole-set agent-facade selector for Antigravity CLI";
          antigravity-ide = lib.mkEnableOption "the whole-set agent-facade selector for Antigravity IDE";
          qwen-code = lib.mkEnableOption "the whole-set agent-facade selector for Qwen Code";
          opencode = lib.mkEnableOption "the whole-set agent-facade selector for OpenCode";
        };
      };
      default = { };
      description = ''
        Per-client whole-set facade selectors. Every flag defaults to false;
        a true flag renders only agent-facade for that client and leaves every
        unselected client's regular and on-demand MCP sets unchanged. The
        legacy facadeCanary switch takes precedence and selects every client.
        Antigravity IDE is reserved but cannot be selected until its native
        environment-backed header delivery is verified.
      '';
    };

    facadeServer = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
      description = "Canonical agent-facade server definition used by selected MCP clients.";
    };

    sourceServers = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
      description = "Servers the shared MCP sets are computed from: all of servers, or agent-facade alone on a canary.";
    };
  };

  config = lib.mkMerge [
    {
      programs.aiMcp.facadeServer = facadeServer;
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
    (lib.mkIf anyCanary {
      assertions =
        lib.optionals cfg.facadeCanary [
          {
            assertion = violations == [ ];
            message = "facadeCanary: these servers are enabled beside agent-facade: ${builtins.toJSON violations}";
          }
        ]
        ++ [
          {
            assertion = cfg.gatewayBaseUrl != null;
            message = "facadeCanaryClients: programs.aiMcp.gatewayBaseUrl must be set; agent-facade is a gateway route";
          }
          {
            assertion = !cfg.facadeCanaryClients."antigravity-ide";
            message = "facadeCanaryClients.antigravity-ide is unavailable until native environment-backed header delivery is verified";
          }
        ];
    })
    # Group attachments are a Claude-only channel. Clear them only when Claude
    # itself is selected, or when the legacy selector selects every client.
    (lib.mkIf (cfg.facadeCanary || cfg.facadeCanaryClients.claude) (
      # Module sets that import module.nix without agent-skills must still evaluate.
      lib.optionalAttrs (options.programs ? agentSkills) {
        programs.agentSkills.groupMcpServers = lib.mkForce { };
      }
    ))
  ];
}
