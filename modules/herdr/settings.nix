#
# herdr Module — config.toml and agent-detection manifests
#
# config.toml is merged with runtime values at activation when mutableSettings
# is true; otherwise it is linked from the Nix store. Agent manifests remain
# declarative home.file entries in both modes.
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
  configToml = tomlFormat.generate "herdr-config.toml" merged;

  manifestFiles = lib.mapAttrs' (
    name: value:
    lib.nameValuePair "${cfg.configDir}/agent-detection/${name}.toml" {
      source = tomlFormat.generate "herdr-agent-${name}.toml" value;
    }
  ) cfg.agentManifests;
in
{
  config = lib.mkIf cfg.enable {
    home.activation = lib.optionalAttrs cfg.mutableSettings {
      herdrConfigMerge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        export PATH="${pkgs.jq}/bin:${pkgs.yj}/bin:$PATH"
        $DRY_RUN_CMD ${../scripts/merge-toml-settings.sh} \
          "${configToml}" \
          "$HOME/${cfg.configDir}/config.toml"
      '';
    };

    home.file =
      lib.optionalAttrs (!cfg.mutableSettings) {
        "${cfg.configDir}/config.toml".source = configToml;
      }
      // manifestFiles;
  };
}
