{
  pkgs,
  lib,
  fetchFromGitHub,
}:

# v0.80.9+ requires go >= 1.25.8; use go_1_26 which satisfies that constraint
(pkgs.buildGoModule.override { go = pkgs.go_1_26; }) rec {
  pname = "gh-aw";
  # managed by: nix-update (deps-update-flake.yml)
  version = "0.80.9";

  src = fetchFromGitHub {
    owner = "github";
    repo = "gh-aw";
    rev = "v${version}"; # Use commit SHA if no tags exist
    hash = "sha256-2BGFKy/X8j0jYQc+W2rLZmZmPgCvZ+QOZweQaAQQJLM=";
  };

  vendorHash = "sha256-jxh8R/X12/QHxZOIKsTvS6FcDQSmJ7RJEvDnJuUr93A=";

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
