# Shared MCP Home Manager module
#
# This module is the single declarative source for MCP server definitions.
# Client modules translate programs.aiMcp.servers into their own config format.
{ config, lib, ... }:

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
      default = import ./catalog.nix;
      description = "Shared MCP server definitions consumed by AI client modules.";
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
    enabledServers = lib.filterAttrs (
      name: server: !(server.disabled or false) && !(lib.elem name config.programs.aiMcp.excludedServers)
    ) config.programs.aiMcp.servers;
    enabledServerNames = lib.attrNames config.programs.aiMcp.enabledServers;
  };
}
