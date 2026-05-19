{
  pkgs,
  lib,
  fetchFromGitHub,
}:

# v0.74.4+ requires go >= 1.25.8; use go_1_26 which satisfies that constraint
(pkgs.buildGoModule.override { go = pkgs.go_1_26; }) rec {
  pname = "gh-aw";
  # managed by: nix-update (deps-update-flake.yml)
  version = "0.74.4";

  src = fetchFromGitHub {
    owner = "github";
    repo = "gh-aw";
    rev = "v${version}"; # Use commit SHA if no tags exist
    hash = "sha256-7sgthC86Ul5Ai6gz7jgErSAEQ+tWRjSypVZixedT3GY=";
  };

  vendorHash = "sha256-TcWrx1ZPFAHZEx7Lc+nbyj0U6WwKZ4ylPgisqqEdwH8=";

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
