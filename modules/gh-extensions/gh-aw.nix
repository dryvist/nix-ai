{
  pkgs,
  lib,
  fetchFromGitHub,
}:

# v0.73.0+ requires go >= 1.25.8; use go_1_26 which satisfies that constraint
(pkgs.buildGoModule.override { go = pkgs.go_1_26; }) rec {
  pname = "gh-aw";
  # managed by: nix-update (deps-update-flake.yml)
  version = "0.73.0";

  src = fetchFromGitHub {
    owner = "github";
    repo = "gh-aw";
    rev = "v${version}"; # Use commit SHA if no tags exist
    hash = "sha256-z3rBRrIQTLjoCGmoiPKwo/uJVpuZCGznwSB1jyDk24g=";
  };

  vendorHash = "sha256-vX9lsuPHBGHNKUh0yuIpVIO2PUOYKYu0ALHApaBjtKs=";

  # Build from cmd/gh-aw directory
  subPackages = [ "cmd/gh-aw" ];

  meta = with lib; {
    description = "GitHub Agentic Workflows CLI extension";
    homepage = "https://github.com/github/gh-aw";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.darwin ++ platforms.linux;
  };
}
