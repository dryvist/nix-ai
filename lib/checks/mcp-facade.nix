# Keep facade checks grouped at the MCP entry point while each focused check
# stays below the repository's per-file size ceiling.
args:
(import ./mcp-facade-effective.nix args)
// (import ./mcp-facade-selectors.nix args)
// (import ./mcp-facade-merges.nix args)
