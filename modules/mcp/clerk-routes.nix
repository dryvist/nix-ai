{
  config,
  lib,
  ...
}:
let
  endpoint = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.strMatching "https?://.+";
        description = "Complete agentgateway MCP endpoint supplied by the consumer.";
      };
      env_http_headers = lib.mkOption {
        type = lib.types.addCheck (lib.types.attrsOf (lib.types.strMatching "[A-Za-z_][A-Za-z0-9_]*")) (
          headers: headers != { }
        );
        description = "Gateway identity headers mapped to runtime environment variable names.";
      };
    };
  };
in
{
  options.programs.aiMcp.clerkRoutes =
    lib.genAttrs
      [
        "vikunja-clerk"
        "zammad-clerk"
      ]
      (
        name:
        lib.mkOption {
          type = lib.types.nullOr endpoint;
          default = null;
          description = ''
            Optional ${name} write endpoint through agentgateway. The consumer supplies
            the published endpoint and caller identity mapping; null leaves it absent.
          '';
        }
      );

  config.programs.aiMcp.servers = lib.mapAttrs (_: route: route // { type = "http"; }) (
    lib.filterAttrs (_: route: route != null) config.programs.aiMcp.clerkRoutes
  );
}
