{ config, lib, ... }:

let
  cfg = config.programs.claude;
  groups = cfg.repoGroups;
  knownPluginIds = builtins.attrNames cfg.plugins.enabled;
  groupDirectories = lib.concatLists (map (group: group.directories) (builtins.attrValues groups));
  emptyGroups = builtins.filter (group: group.directories == [ ]) (builtins.attrValues groups);
  groupPluginIds = lib.concatLists (map (group: group.plugins) (builtins.attrValues groups));
  unknownPluginIds = builtins.filter (
    pluginId: !(builtins.elem pluginId knownPluginIds)
  ) groupPluginIds;

  isSafeRelativeDirectory =
    directory:
    directory != ""
    && !(lib.hasPrefix "/" directory)
    && builtins.all (component: component != "" && component != "." && component != "..") (
      lib.splitString "/" directory
    );

  renderSettings = group: {
    enabledPlugins = builtins.listToAttrs (
      map (pluginId: {
        name = pluginId;
        value = builtins.elem pluginId group.plugins;
      }) knownPluginIds
    );
  };

  renderGroupFiles =
    group:
    map (directory: {
      name = "${directory}/.claude/settings.json";
      value.text = builtins.toJSON (renderSettings group);
    }) group.directories;
in
{
  options.programs.claude.repoGroups = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          directories = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            example = [
              "git/public/nix-ai"
              "git/worktrees/nix-ai"
            ];
            description = "Workspace directories relative to the user's home directory.";
          };

          plugins = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [ "ansible-workflows@lunar-claude" ];
            description = "Plugin IDs enabled for this repository.";
          };
        };
      }
    );
    default = { };
    example = {
      nix = {
        directories = [
          "git/public/nix-ai"
          "git/worktrees/nix-ai"
        ];
        plugins = [ "terraform-module-builder@claude-code-plugins-plus" ];
      };
    };
    description = ''
      Named repository groups rendered as native Claude Code project settings
      at each <directory>/.claude/settings.json for its listed workspace
      directories, which are relative to the user's home directory. For each group,
      every plugin ID configured in programs.claude.plugins.enabled is written
      as enabled or disabled, so plugins outside the group's list are disabled
      for those repositories. An empty value (the default) writes no repository
      settings files and preserves the user-level plugin configuration.

      This option writes only the shared .claude/settings.json file. It never
      writes .claude/settings.local.json.

      Claude Code reads shared project settings from the session's primary
      working directory. Start Claude Code at the repository root for a root
      .claude/settings.json to apply. See
      https://code.claude.com/docs/en/settings.

      Home Manager's normal collision check rejects a differing unmanaged
      .claude/settings.json at a configured path; it does not force or replace
      it. Remove the unmanaged file or fold its desired settings into this
      configuration before activating the group.
    '';
  };

  config = lib.mkIf (groups != { }) {
    assertions = [
      {
        assertion = builtins.all isSafeRelativeDirectory groupDirectories;
        message = "programs.claude.repoGroups directories must be safe relative paths under the home directory.";
      }
      {
        assertion = emptyGroups == [ ];
        message = "Every programs.claude.repoGroups entry must list at least one workspace directory.";
      }
      {
        assertion = builtins.length groupDirectories == builtins.length (lib.unique groupDirectories);
        message = "programs.claude.repoGroups must not assign multiple groups to the same directory.";
      }
      {
        assertion = unknownPluginIds == [ ];
        message = "programs.claude.repoGroups references plugin IDs not configured in programs.claude.plugins.enabled: ${builtins.toJSON unknownPluginIds}";
      }
    ];

    # Leave `force` unset so Home Manager's collision check protects unmanaged files.
    home.file = builtins.listToAttrs (
      lib.concatLists (map renderGroupFiles (builtins.attrValues groups))
    );
  };
}
