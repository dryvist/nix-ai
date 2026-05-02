# Shared MCP Home Manager module
#
# This module is the single declarative source for MCP server definitions.
# Client modules translate programs.aiMcp.servers into their own config format.
{ lib, ... }:

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
  };
}
