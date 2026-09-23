# npm-published MCP servers packaged as Nix derivations with a local defect
# patch applied — the same "own the store copy, not a live bunx pull"
# rationale as packages.nix, but for a server whose upstream needs a fix
# nix-ai carries locally.
#
# vikunja-mcp ships no package-lock.json in its npm tarball, so
# patches/vikunja-mcp-0.2.0-package-lock.json is a checked-in lock generated
# once (npm install --package-lock-only --ignore-scripts against the
# unpatched tarball; the defect patch below only touches compiled dist/
# files, never package.json, so the lock stays valid post-patch). It's
# copied into place in postPatch so buildNpmPackage's own npmConfigHook can
# validate it against fetchNpmDeps's fixed-output cache — the standard
# nixpkgs way to do a network install inside Nix's sandbox, replacing the
# hand-rolled FOD + npm-install scripts this module used to carry. Bump
# npmDepsHash to lib.fakeHash and rebuild to get the real one after any
# version or lockfile change.
{ pkgs }:
let
  inherit (pkgs) lib;
  versions = import ../../lib/versions.nix;
  version = versions.vikunjaMcp;
in
{
  vikunja-mcp = pkgs.buildNpmPackage {
    pname = "vikunja-mcp";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/@democratize-technology/vikunja-mcp/-/vikunja-mcp-${version}.tgz";
      hash = "sha256-xhl4lSKT+bXZj76JqP218WLSS6Com8zWSAHa+9i53LQ=";
    };

    # Defect patch from Vikunja task 3413: sequential bulk-create (avoids
    # server-side task-index races), allProjects fan-out (avoids /tasks/all's
    # 500), update projectId (was a silent no-op), and an optional `fields`
    # filter on `list` (the raw project list was reported as huge).
    patches = [ ../../patches/vikunja-mcp-0.2.0-defects.patch ];

    postPatch = ''
      cp ${../../patches/vikunja-mcp-0.2.0-package-lock.json} package-lock.json
    '';

    npmDepsHash = "sha256-ta7VCb0k+1hB3VesAVYRsa2V/2UzWVBvaywE5vOPHOo=";

    # dist/ ships prebuilt in the npm tarball (patched above); there is no
    # source or build script to run. `npm pack` (used by the install hook to
    # list files) still fires "prepack"/"prepare" by default, which would
    # try to run the missing tsc build -- skip it.
    dontNpmBuild = true;
    npmPackFlags = [ "--ignore-scripts" ];

    nativeCheckInputs = [ pkgs.nodejs ];
    doCheck = true;
    checkPhase = ''
      runHook preCheck
      VIKUNJA_MCP_DIST="$PWD/dist" node --test \
        ${../../patches/test-bulk-update-no-clobber.mjs} \
        ${../../patches/test-update-done.mjs} \
        ${../../patches/test-update-field-value-rejected.mjs}
      runHook postCheck
    '';

    meta = {
      description = "Vikunja MCP server, patched for task 3413's defects";
      homepage = "https://github.com/democratize-technology/vikunja-mcp";
      license = lib.licenses.mit;
      mainProgram = "vikunja-mcp";
    };
  };
}
