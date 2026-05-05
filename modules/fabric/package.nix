#
# Fabric CLI Package
#
# Daniel Miessler's Fabric (github.com/danielmiessler/fabric) — Go CLI providing
# 252+ reusable AI prompt patterns for analysis, extraction, summarization, code
# review, and content transformation.
#
# Pinned to a specific release tag. Version bumps managed by Renovate via the
# datasource annotation above the version string.
#
# Naming: "fabric-ai" avoids collision with the unrelated Python `fabric` package
# in nixpkgs (pythonic remote execution). Both can coexist on PATH since the
# binary name is still `fabric`.
#
# Build strategy: standard buildGoModule (not upstream's gomod2nix) to keep our
# flake self-contained. Run `nix build` once with an empty vendorHash, then
# replace with the correct hash from the error message.
#
{
  lib,
  buildGoModule,
  installShellFiles,
  fabric-src,
}:

buildGoModule rec {
  pname = "fabric-ai";
  version = (import ../../lib/versions.nix).fabric;

  src = fabric-src;

  # Discover via: nix build .#fabric-ai 2>&1 | grep 'got:'
  vendorHash = "sha256-G1N/cPPReI5jrZ9orrWEAV/cRPrGbUZyhht+8iMDRb0=";

  # Build only the main fabric binary from cmd/fabric. Skip cmd/code2context,
  # cmd/generate_changelog, cmd/to_pdf — we only need the primary CLI.
  subPackages = [ "cmd/fabric" ];

  # Strip debug symbols for smaller binary (matches upstream flake)
  ldflags = [
    "-s"
    "-w"
  ];

  nativeBuildInputs = [ installShellFiles ];

  # Skip tests during build — they require network access to AI providers
  doCheck = false;

  # Fabric uses go-flags (no built-in completion generator). Install a hand-
  # written zsh completion that uses --shell-complete-list for dynamic values.
  postInstall = ''
    installShellCompletion --zsh --name _fabric ${./completions/_fabric}
  '';

  # Prevent Go from downloading a different toolchain version
  env.GOTOOLCHAIN = "local";

  meta = {
    description = "Open-source framework for augmenting humans using AI (252+ prompt patterns)";
    homepage = "https://github.com/danielmiessler/fabric";
    license = lib.licenses.mit;
    mainProgram = "fabric";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
