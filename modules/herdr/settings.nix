#
# herdr Module — config.toml and agent-detection manifests
#
# Both are plain declarative home.file entries. herdr does not rewrite its own
# config.toml (session state lives under its state dir), so no deep-merge
# activation is needed — unlike Codex and Antigravity, which do.
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.herdr;
  tomlFormat = pkgs.formats.toml { };

  # `remotes` / `defaultRemote` are conveniences over the same [remote] section
  # `settings` can write directly. Merged so an explicit `settings.remote` wins.
  remoteSection = lib.optionalAttrs (cfg.remotes != { }) {
    remote = {
      hosts = cfg.remotes;
    }
    // lib.optionalAttrs (cfg.defaultRemote != null) { default = cfg.defaultRemote; };
  };

  merged = lib.recursiveUpdate remoteSection cfg.settings;

  manifestFiles = lib.mapAttrs' (
    name: value:
    lib.nameValuePair "${cfg.configDir}/agent-detection/${name}.toml" {
      source = tomlFormat.generate "herdr-agent-${name}.toml" value;
    }
  ) cfg.agentManifests;
in
{
  config = lib.mkIf cfg.enable {
    home.file = {
      "${cfg.configDir}/config.toml".source = tomlFormat.generate "herdr-config.toml" merged;
    }
    // manifestFiles;
  };
}
