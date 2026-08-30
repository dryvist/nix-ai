# Tier 3 — Personal (author's own plugins; preferred over community and specialty tiers).
# Tier 3 — Personal (author's own plugins)
#
# Duplicate Resolution Rule:
#   Plugins in this file are PREFERRED over Tiers 4, 5.
#   Plugins in this file are SUPERSEDED by Tiers 1, 2.
#
# Marketplaces in this tier:
#   - jacobpevans-cc-plugins (JacobPEvans/claude-code-plugins, 2★)
#       Plugins are auto-discovered from the flake input at evaluation time.
#       The list is determined by the repository contents (any directory
#       containing .claude-plugin/plugin.json is registered).
#
# To disable a specific jacobpevans plugin, override it explicitly below:
#   "<plugin-name>@jacobpevans-cc-plugins" = false;

{
  lib,
  jacobpevans-cc-plugins,
  ...
}:

let
  entries = builtins.readDir jacobpevans-cc-plugins;
  # Plugin directories: exclude dotfiles, regular files, and known non-plugin dirs
  nonPluginDirs = [
    "docs"
    "schemas"
    ".claude-plugin"
    ".github"
    "scripts"
    "tests"
  ];
  isPluginDir =
    name: type:
    type == "directory"
    && !(lib.hasPrefix "." name)
    && !(builtins.elem name nonPluginDirs)
    && builtins.pathExists "${jacobpevans-cc-plugins}/${name}/.claude-plugin/plugin.json";
  pluginNames = builtins.attrNames (lib.filterAttrs isPluginDir entries);
  jacobpevansPlugins = lib.genAttrs (map (name: "${name}@jacobpevans-cc-plugins") pluginNames) (
    _: true
  );
in
{
  enabledPlugins = jacobpevansPlugins // {
    # Per-plugin overrides go here (e.g., to disable a specific plugin):
    # "<plugin-name>@jacobpevans-cc-plugins" = false;

    # config-management: DISABLED. Both skills it ships (quick-add-permission,
    # sync-permissions) are self-described as deprecated — permissions moved to
    # nix-claude-code and permission sync is retired — and it records zero uses.
    # Its skill descriptions still cost listing budget on every session start.
    "config-management@jacobpevans-cc-plugins" = false;
  };
}
