{
  pkgs,
  lib,
  fetchFromGitHub,
}:

# v0.82.1+ requires go >= 1.25.8; use go_1_26 which satisfies that constraint
(pkgs.buildGoModule.override { go = pkgs.go_1_26; }) rec {
  pname = "gh-aw";
  # managed by: nix-update (deps-update-flake.yml)
  version = "0.82.1";

  src = fetchFromGitHub {
    owner = "github";
    repo = "gh-aw";
    rev = "v${version}"; # Use commit SHA if no tags exist
    hash = "sha256-df/V5wFcRqLpWAvL0ilYs2cB/8b9ae7PN1mUXsh+NkY=";
  };

  vendorHash = "sha256-fDt1ETeYE2AV/SWkzuYe5GWyFD1/y9kpJw/JT35hxno=";

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
