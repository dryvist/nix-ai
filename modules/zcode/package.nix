# ZCode CLI (zai-org/ZCode `apps/zcode-cli`), built from the release tag.
#
# Upstream ships the CLI as a Node SEA: build-sea.mjs downloads a Node binary
# and embeds prebuilt rg/bfs/ugrep archives vendored under
# apps/zcode-cli/dependencies/. Neither step runs here. The plain CLI build
# (packages/cli/scripts/build.mjs, the step build:sea runs first) produces
# dist/zcode.cjs, which runs on nixpkgs Node from the built workspace tree.
# Outside a SEA the CLI resolves its search tools as bare `rg`, `bfs` and
# `ugrep` on PATH (bootstrap/src/app/embedded-search-backend.ts), so the
# wrapper prepends the nixpkgs builds and the vendored archives are not copied.
#
# The tree keeps its monorepo layout because the CLI finds its provider
# config, bundled skills and official plugins relative to dist/zcode.cjs.
#
# After a Renovate bump of lib/versions.nix `zcode`, fix-renovate-hashes.yml
# rewrites both hashes below with nix-update.
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  nodejs_24,
  makeWrapper,
  ripgrep,
  bfs,
  ugrep,
  version,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "zcode";
  version = lib.removePrefix "v" version;

  src = fetchFromGitHub {
    owner = "zai-org";
    repo = "ZCode";
    tag = "v${finalAttrs.version}";
    hash = "sha256-4LZIl6ofaxcmb28fu21Kc5oJAe+/AKRDAM/2xRKYxI8=";
  };

  # Upstream's .npmrc sets node-linker=hoisted, under which pnpm links every
  # workspace's dependencies whatever the --filter, so the whole lockfile is
  # fetched and installed (about 3.4 GiB). Only the build below is filtered.
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 4;
    hash = "sha256-q2ClqOoSG0/Oyi4H9snIUc0AVk5y40V+optxyMBfzn8=";
  };

  nativeBuildInputs = [
    nodejs_24
    pnpm_10
    pnpmConfigHook
    makeWrapper
  ];

  # The hoisted layout nests a node_modules per workspace, and pnpmConfigHook
  # patches only the root one; the Linux sandbox has no /usr/bin/env.
  preBuild = ''
    patchShebangs --build .
  '';

  # The CLI and the two official plugins it seeds from the filesystem, each
  # with its workspace dependencies, in topological order.
  buildPhase = ''
    runHook preBuild
    pnpm --filter '@zcode/cli...' --filter '@zcode/node-repl-host...' \
      --filter '@zcode/browser-use-plugin...' run build
    runHook postBuild
  '';

  # The tree is mostly prebuilt node_modules binaries; stripping them buys
  # nothing and breaks the ad-hoc signatures on darwin.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    rm -rf apps/zcode-cli/dependencies
    rm apps/zcode-cli/packages/cli/dist/zcode.cjs.map
    mkdir -p $out/lib
    cp -r . $out/lib/zcode
    makeWrapper ${lib.getExe nodejs_24} $out/bin/zcode \
      --add-flags $out/lib/zcode/apps/zcode-cli/packages/cli/dist/zcode.cjs \
      --prefix PATH : ${
        lib.makeBinPath [
          ripgrep
          bfs
          ugrep
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Z.ai coding agent CLI";
    homepage = "https://github.com/zai-org/ZCode";
    license = lib.licenses.asl20;
    mainProgram = "zcode";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
})
