#
# Qwen Code Module — Package Install
#
# Brew-only install. The formula is declared by nix-darwin's
# homebrew.brews block, sourced from this flake's lib.brewFormulae
# output. This module just contributes a soft activation check that
# warns if the formula isn't installed yet (e.g., the user enabled the
# home-manager module but hasn't run the companion nix-darwin rebuild).
#
# A buildNpmPackage derivation was attempted but qwen-code's workspace
# layout + cross-platform optionalDependencies (six per-OS @lydell/
# node-pty wheels + transitive ENOTCACHED gaps) needs deeper packaging
# work than this PR's scope. Brew works fine on darwin, which is the
# only platform that ships qwen-code today; Linux hosts need brew /
# Linuxbrew to use this module.
#
{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.programs.qwen-code;
in
{
  config = lib.mkIf cfg.enable {
    # Eval-time gate: the only implemented installVia is "brew", which
    # only works on darwin (homebrew.brews lives in nix-darwin). Linux
    # hosts must leave the module disabled until a buildNpmPackage path
    # ships, or install qwen-code manually via Linuxbrew or distro pkg.
    assertions = [
      {
        assertion = cfg.installVia != "brew" || pkgs.stdenv.isDarwin;
        message = ''
          programs.qwen-code.installVia = "brew" requires darwin
          (brew formula lives in nix-darwin's homebrew.brews).
          Linux hosts: leave programs.qwen-code disabled until the
          buildNpmPackage path lands, or install qwen-code manually
          via your distro's package manager / Linuxbrew.
        '';
      }
    ];

    # Soft activation-time warning, darwin-only — fires when the user
    # enabled this module but hasn't run the companion nix-darwin
    # rebuild yet, so the brew-installed binary isn't on PATH.
    home.activation = lib.optionalAttrs pkgs.stdenv.isDarwin {
      checkQwenInstalled = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD ${pkgs.bash}/bin/bash ${./scripts/check-qwen-installed.sh}
      '';
    };
  };
}
