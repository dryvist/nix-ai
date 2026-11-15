{ pkgs }:
pkgs.buildNpmPackage rec {
  pname = "mcp-remote";
  version = (import ../../lib/versions.nix).mcpRemote;
  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/mcp-remote/-/mcp-remote-${version}.tgz";
    hash = "sha256-gu+cyMKsoh9gp1UTdDFdKBz0KLQ4nX8Xn7WJPd9CWys=";
  };
  postPatch = ''
    cp ${../../patches/mcp-remote-0.15.2-package-lock.json} package-lock.json
  '';
  npmDepsHash = "sha256-hOQ2zKS9cLFY18AIjA2nbJUsACokZUlekDeipTtB8WY=";
  dontNpmBuild = true;
  npmPackFlags = [ "--ignore-scripts" ];
  meta.mainProgram = "mcp-remote";
}
