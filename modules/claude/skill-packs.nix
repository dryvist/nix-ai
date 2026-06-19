# Skill packs — render the named project-scoped plugin packs and install the
# `ai-pack` importer.
#
# Packs (modules/claude/plugins/packs.nix) are the single source of truth. Each
# is rendered to ~/.config/ai-packs/<name>.json (declarative home.file, so stale
# packs are auto-pruned on rebuild). `ai-pack <name>` merges one into the current
# repo's committed .claude/settings.json. See docs/architecture/plugin-scoping.md.
{ lib, pkgs, ... }:
let
  packs = import ./plugins/packs.nix;

  ai-pack = pkgs.writeShellApplication {
    name = "ai-pack";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./scripts/ai-pack.sh;
  };
in
{
  home.packages = [ ai-pack ];

  home.file = lib.mapAttrs' (name: plugins: {
    name = ".config/ai-packs/${name}.json";
    value.text = builtins.toJSON { enabledPlugins = plugins; } + "\n";
  }) packs;
}
