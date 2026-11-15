{ pkgs }:
pkgs.buildNpmPackage rec {
  pname = "mcp-remote";
  version = (import ../../lib/versions.nix).mcpRemote;
  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/mcp-remote/-/mcp-remote-${version}.tgz";
    hash = "sha256-gu+cyMKsoh9gp1UTdDFdKBz0KLQ4nX8Xn7WJPd9CWys=";
  };
  postPatch = ''
    cp ${../../patches + "/mcp-remote-${version}-package-lock.json"} package-lock.json
  '';
  npmDepsHash = "sha256-t4BvpAX6El4A22f/SmScZd4n6qR53EBy6i6vIRMo6Ms=";
  dontNpmBuild = true;
  npmPackFlags = [ "--ignore-scripts" ];
  meta.mainProgram = "mcp-remote";
}
