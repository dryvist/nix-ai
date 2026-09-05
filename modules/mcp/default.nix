# Shared MCP Home Manager module
#
# This module is the single declarative source for MCP server definitions.
# Client modules translate programs.aiMcp.servers into their own config format.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  mcpServerModule = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum [
          "stdio"
          "sse"
          "http"
        ];
        default = "stdio";
      };
      command = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
      };
      env_vars = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      # Servers that report which agent runtime invoked them need a different
      # value per client, which `env` (one attrset shared by every renderer)
      # cannot express. Naming the variable here lets modules/mcp/client.nix
      # fill in each client's own name as it renders.
      clientNameEnv = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      cwd = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      headers = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
      };
      timeout = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
      };
      startup_timeout_sec = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
      };
      tool_timeout_sec = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
      };
      disabled = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      required = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
      };
      enabled_tools = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      disabled_tools = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      bearer_token_env_var = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      env_http_headers = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
      };
      http_headers = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
      };
      oauth_resource = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      scopes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };
in
{
  options.programs.aiMcp = {
    servers = lib.mkOption {
      type = lib.types.attrsOf mcpServerModule;
      default = { };
      description = ''
        Shared MCP server definitions consumed by AI client modules. The shared
        catalog is assigned below in `config` (a plain priority-100 definition)
        rather than as this option's `default`, because an option default does
        NOT merge with a partial definition: a consumer setting
        `programs.aiMcp.servers.<name>.disabled = lib.mkForce false` would
        otherwise discard the whole catalog and keep only that one entry. As a
        config-level assignment the catalog merges per-server, so hosts can
        override an individual server with `lib.mkForce`.
      '';
    };

    excludedServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cloudflare"
        "cribl"
        "docker"
        "everything"
        "exa"
        "fetch"
        "filesystem"
        "firecrawl"
        "git"
        "github"
        "terraform"
      ];
      description = "MCP servers excluded from the global cross-agent MCP profile.";
    };

    onDemandServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "apple-events"
        "zammad"
        # Added on measured usage across 1,651 local transcripts: vikunja is
        # called 2,296 times, an order of magnitude more than any of these
        # four (codex 149, fabric 124, grep 117, time 54). They cost 5,474
        # tokens of every session between them, so a session that calls none
        # of them — most sessions — pays 5,474 for nothing.
        "codex"
        "fabric"
        "grep"
        "time"
      ];
      description = ''
        MCP servers kept out of every session's always-on profile and attached
        only by a session that needs them.

        Measured on this stack (`claude -p "reply OK"`, first-request tokens,
        in nix-ai): the always-on profile costs 37,499 tokens with all seven
        local servers against 5,474 with only codex/fabric/grep/time. zammad
        accounts for 22,139 of that and apple-events for 6,746 — together
        roughly 26% of a session's entire context, in repositories that never
        call either one.

        The MCP block is the largest addressable cost in a session and it is
        repo-independent: 32,622 in nix-ai, 35,210 in tofu-proxmox, 33,045 in
        docs-starlight. All three repos measure UNDER the 90k budget with no
        MCP and OVER it with. For comparison the entire skill listing is
        12–15k, so MCP is more than double the block this stack spent most of
        its optimisation effort on.

        Membership here is decided by recorded usage, never by judgment about
        what a session "might" want — the same rule the skill keep-list
        follows, and for the same reason.

        Nothing becomes unreachable. Every server listed here is still rendered
        to `~/.claude/mcp-available/<name>.json`, ready to attach:

          claude --mcp-config ~/.claude/mcp-available/zammad.json

        A server that a repository needs in every session belongs in the
        always-on profile instead — remove it from this list.
      '';
    };

    onDemandEnabledServers = lib.mkOption {
      type = lib.types.attrsOf mcpServerModule;
      readOnly = true;
      internal = true;
      description = "On-demand servers, resolved and platform-filtered; rendered per client for attach-on-demand.";
    };

    enabledServers = lib.mkOption {
      type = lib.types.attrsOf mcpServerModule;
      readOnly = true;
      internal = true;
      description = "Shared MCP servers enabled after applying global exclusions and disabled flags.";
    };

    enabledServerNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      internal = true;
      description = "Names of shared MCP servers enabled after applying global exclusions and disabled flags.";
    };
  };

  config.programs.aiMcp = {
    # Plain (priority-100) assignment so per-server host overrides merge — see
    # the `servers` option description above.
    servers = import ./catalog.nix {
      inherit (config.home) homeDirectory;
      inherit pkgs;
    };
    enabledServers = lib.filterAttrs (
      name: server:
      !(server.disabled or false)
      && !(lib.elem name config.programs.aiMcp.excludedServers)
      && !(lib.elem name config.programs.aiMcp.onDemandServers)
      && !(name == "apple-events" && !pkgs.stdenv.isDarwin)
    ) config.programs.aiMcp.servers;
    onDemandEnabledServers = lib.filterAttrs (
      name: server:
      !(server.disabled or false)
      && !(lib.elem name config.programs.aiMcp.excludedServers)
      && lib.elem name config.programs.aiMcp.onDemandServers
      && !(name == "apple-events" && !pkgs.stdenv.isDarwin)
    ) config.programs.aiMcp.servers;
    enabledServerNames = lib.attrNames config.programs.aiMcp.enabledServers;
  };
}
