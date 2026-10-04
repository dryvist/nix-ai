# Shared MCP server option schema.
{ lib }:

lib.types.submodule {
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
    # argv prepended to `command` at render time, e.g. a wrapper that
    # supplies `env_vars`. Where the values come from is the consumer's
    # concern; this module only splices the list in.
    launchPrefix = lib.mkOption {
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
    clientNameEnvValues = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Optional per-renderer value mapping for clientNameEnv; unmapped clients keep their renderer name.";
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
}
