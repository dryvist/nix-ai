{
  pkgs,
  lib,
  fetchFromGitHub,
}:

# v0.75.3+ requires go >= 1.25.8; use go_1_26 which satisfies that constraint
(pkgs.buildGoModule.override { go = pkgs.go_1_26; }) rec {
  pname = "gh-aw";
  # managed by: nix-update (deps-update-flake.yml)
  version = "0.75.3";

  src = fetchFromGitHub {
    owner = "github";
    repo = "gh-aw";
    rev = "v${version}"; # Use commit SHA if no tags exist
    hash = "sha256-zVUjj2X0IM+j+5ZnwcpzqSYXx6vHe2OMcGUT4uCmJcs=";
  };

  vendorHash = "sha256-ke1gGS6Y7zviNap6olhKK4O6wuH9ROjT0/i/+HGqIkM=";

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
