{
  description = "MCP runtime + server definitions for AI CLI tools (sub-flake of nix-ai)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    pal-mcp-server = {
      url = "github:BeehiveInnovations/pal-mcp-server";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      pal-mcp-server,
      ...
    }:
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
      # (pal-mcp wrapper, doppler-mcp, sync helpers, PAL activations).
      # `default` is the bare module; `withArgs` pre-injects the
      # `pal-mcp-server` flake input so consumers don't need to thread it.
      homeManagerModules = {
        default = ./module.nix;

        withArgs = {
          imports = [ ./module.nix ];
          _module.args = { inherit pal-mcp-server; };
        };
      };

      # PAL Python build, callable from the consumer's pkgs.
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          pal-mcp-server = pkgs.callPackage ./pal-package.nix { inherit pal-mcp-server; };
        }
      );

      # Sub-flake checks: pal-package build + cloud-sync shellcheck.
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./checks.nix { inherit pkgs pal-mcp-server; }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
