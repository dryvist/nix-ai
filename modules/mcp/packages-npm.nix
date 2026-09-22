# npm-published MCP servers packaged as Nix derivations with a local defect
# patch applied — the same "own the store copy, not a live bunx pull"
# rationale as packages.nix, but for a server whose upstream needs a fix
# nix-ai carries locally.
#
# vikunja-mcp ships no package-lock.json in its npm tarball, so npmDepsHash
# has no lock to hash against. node_modules is instead built as its own
# fixed-output derivation (`vikunjaMcpNodeModules`): `npm install` runs
# inside the FOD sandbox, which nix's own network-sandboxed build isolation
# (not the workstation's ambient "no interactive package installs" policy)
# already governs, and the result is pinned by `outputHash`. Bump
# `outputHash` to `pkgs.lib.fakeHash` and rebuild to get the real one after
# any version bump.
{ pkgs }:
let
  lib = pkgs.lib;
  versions = import ../../lib/versions.nix;
  version = versions.vikunjaMcp;

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@democratize-technology/vikunja-mcp/-/vikunja-mcp-${version}.tgz";
    hash = "sha256-xhl4lSKT+bXZj76JqP218WLSS6Com8zWSAHa+9i53LQ=";
  };

  # Defect patch from Vikunja task 3413: sequential bulk-create (avoids
  # server-side task-index races), allProjects fan-out (avoids /tasks/all's
  # 500), update projectId (was a silent no-op), and an optional `fields`
  # filter on `list` (the raw project list was reported as huge).
  patchedSrc = pkgs.runCommand "vikunja-mcp-${version}-patched" { } ''
    bash ${./scripts/vikunja-mcp-patch.sh} \
      ${src} \
      ${../../patches/vikunja-mcp-0.2.0-defects.patch} \
      "$out"
  '';

  vikunjaMcpNodeModules = pkgs.stdenvNoCC.mkDerivation {
    pname = "vikunja-mcp-node-modules";
    inherit version;
    src = patchedSrc;
    nativeBuildInputs = [
      pkgs.nodejs
      pkgs.cacert
    ];
    dontInstall = true;
    buildPhase = builtins.readFile ./scripts/vikunja-mcp-node-modules.sh;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    # Placeholder — `nix build .#vikunja-mcp` prints the real hash on
    # mismatch; paste it in on the first build after any version bump.
    outputHash = "sha256-Mb78boPMxf9q1aouJMhXqC+ijdu1OgDxWJlveeCGcFU=";
  };
in
{
  vikunja-mcp = pkgs.stdenvNoCC.mkDerivation {
    pname = "vikunja-mcp";
    inherit version;
    src = patchedSrc;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;
    NODE_BIN = "${pkgs.nodejs}/bin/node";
    installPhase = ''
      set -- "${vikunjaMcpNodeModules}" "$out"
      source ${./scripts/vikunja-mcp-install.sh}
    '';
    meta = {
      description = "Vikunja MCP server, patched for task 3413's defects";
      homepage = "https://github.com/democratize-technology/vikunja-mcp";
      license = lib.licenses.mit;
      mainProgram = "vikunja-mcp";
    };
  };
}
