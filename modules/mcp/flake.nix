{
  description = "MCP runtime + server definitions for AI CLI tools (sub-flake of nix-ai)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
  };

  outputs =
    { nixpkgs, ... }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      # MCP server definitions (attrset of stdio/http servers).
      # Pure data; consumed by the home-manager module via
      # `programs.<tool>.mcpServers = inputs.nix-ai-mcp.lib.mcpServers;`.
      lib.mcpServers = import ./default.nix;

      # Home-manager module that owns all MCP runtime infrastructure
      # (doppler-mcp wrapper, splunk-mcp-connect). Importing it alone gives a
      # consumer a working MCP runtime with no cross-tool runtime dependencies
      # on Claude or Codex.
      homeManagerModules.default = ./module.nix;

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
