# Shared formatter utility functions
{ lib }:

let
  # Flatten nested attribute sets into a list of commands
  # Handles both lists and nested attrsets
  flattenCommands =
    attrs:
    if builtins.isList attrs then
      attrs
    else if builtins.isAttrs attrs then
      lib.flatten (
        lib.mapAttrsToList (
          _name: value:
          if builtins.isList value then
            value
          else if builtins.isAttrs value then
            flattenCommands value
          else
            [ ]
        ) attrs
      )
    else
      [ ];
in
{
  inherit flattenCommands;

  # Count total commands in a permission set
  countCommands = permissions: builtins.length (flattenCommands permissions);

  # Get all categories from permissions
  getCategories = permissions: builtins.attrNames permissions;

  # Normalize MCP server definition to Antigravity format
  normalizeMcpServer =
    server:
    if server.url != null then
      # HTTP/SSE server
      { httpUrl = server.url; } // lib.optionalAttrs (server.headers != { }) { inherit (server) headers; }
    else
      # stdio server
      lib.filterAttrs (_name: value: value != null && value != [ ] && value != { }) {
        inherit (server)
          command
          args
          env
          cwd
          timeout
          ;
      };
}
