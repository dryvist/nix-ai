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
      && !(name == "apple-events" && !pkgs.stdenv.isDarwin)
    ) config.programs.aiMcp.servers;
    enabledServerNames = lib.attrNames config.programs.aiMcp.enabledServers;
  };

  # Catch phantom servers before they reach a renderer.
  #
  # `servers` is an attrsOf submodule, so setting any key on a name the catalog
  # does not define CREATES that server from defaults — `type = "stdio"` with
  # `command = null`. A consumer enabling a server that has since been renamed
  # or removed upstream (`aiMcp.servers.<gone>.disabled = lib.mkForce false`)
  # therefore does not get an error about an unknown server; it gets a silently
  # materialised, unlaunchable one.
  #
  # Downstream that surfaces as a bare "MCP servers with type stdio must have a
  # command set" with no server named, which reads like a catalog bug rather
  # than a stale override in the consumer's own config. This names the server
  # and the likely cause. Applies to every server, not one known-bad name.
  config.assertions =
    let
      phantoms = lib.attrNames (
        lib.filterAttrs (
          _: server: server.type == "stdio" && server.command == null && server.url == null
        ) config.programs.aiMcp.enabledServers
      );
    in
    [
      {
        assertion = phantoms == [ ];
        message = ''
          programs.aiMcp: enabled server(s) with no way to launch: ${lib.concatStringsSep ", " phantoms}

          Each has the submodule defaults (type = "stdio", command = null, url = null),
          which almost always means the name is not in the catalog and an override
          created it. Check for a stale `aiMcp.servers.<name>.disabled = lib.mkForce false`
          naming a server this version of nix-ai no longer defines, or update the
          nix-ai input to one that does.
        '';
      }
    ];
}
