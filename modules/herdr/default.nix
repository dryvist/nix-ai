# herdr Module — Aggregator
#
# herdr (https://github.com/herdrdev/herdr) is a background server that owns
# the terminals coding agents run in: sessions survive reboot and reattach over
# SSH, panes are marked working/blocked/idle, and agents drive it themselves
# through a CLI and a Unix-socket JSON API.
#
# This module is the workstation half. The server half is modules/herdr/nixos.nix,
# exported as nixosModules.herdr; both take their binary from the same
# llm-agents.nix input, which is the whole point — one flake, both setups.
#
# Two things NOT to do, both of which herdr's own quick-start will suggest:
#
#   1. Do not run `herdr integration install <agent>`. It writes lifecycle
#      hooks into each agent's own config — for Claude Code that means editing
#      ~/.claude/settings.json, which nix-claude-code renders read-only from the
#      Nix store. The write fails, or is reverted on the next switch. Express
#      those hooks as programs.claude.hooks in modules/claude-config.nix.
#
#   2. Be aware herdr fetches agent-manifest updates from herdr.dev at runtime
#      and applies them without a restart. Local manifests take precedence, so
#      declare the ones that matter in programs.herdr.agentManifests rather
#      than relying on whatever the network last handed the daemon.
{
  config,
  lib,
  pkgs,
  llm-agents,
  ...
}:

let
  cfg = config.programs.herdr;
  herdrPackage = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
in
{
  imports = [
    ./options.nix
    ./settings.nix
    ./launchd.nix
  ];

  config = lib.mkIf cfg.enable {
    programs.herdr.package = lib.mkDefault herdrPackage;

    home.packages = lib.optional (cfg.package != null) cfg.package;
  };
}
