#
# herdr-hail — LaunchAgent (Slack/Discord bridge)
#
# Hail runs as its own process rather than through herdr's interactive plugin
# host, so it can watch the local control socket without an open TUI.
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.herdr;
  hail = config.services.herdr.hail;
  logDir = "${config.home.homeDirectory}/Library/Logs/herdr";

  # Match hail's upstream defaults; only non-secret config is rendered here.
  settings = lib.recursiveUpdate {
    notifyOn = [
      "blocked"
      "done"
    ];
    pollIntervalMs = 1500;
    contextSource = "visible";
    contextLines = 40;
    slack = {
      enabled = false;
      allowedUsers = [ ];
    };
    discord = {
      enabled = false;
      allowedUsers = [ ];
      messageContent = false;
    };
  } hail.settings;

  configStoreDir = pkgs.writeTextDir "herdr-hail-config/config.json" (builtins.toJSON settings);
in
{
  options.services.herdr.hail.renderedSettings = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    internal = true;
    description = "The config.json attrset this module renders; read by the regression checks.";
  };

  config = lib.mkIf (cfg.enable && cfg.package != null && hail.enable) {
    services.herdr.hail.renderedSettings = settings;

    assertions = [
      {
        assertion = (settings.slack.enabled or false) || (settings.discord.enabled or false);
        message = ''
          services.herdr.hail is enabled but neither settings.slack.enabled nor
          settings.discord.enabled is true. herdr-hail has no environment
          override for those flags, so the bridge would run and deliver nothing.
        '';
      }
      {
        assertion =
          (settings.slack.botToken or null) == null
          && (settings.slack.appToken or null) == null
          && (settings.discord.botToken or null) == null;
        message = "services.herdr.hail tokens must be supplied as launch-time environment variables, not settings.";
      }
    ];

    launchd.agents.herdr-hail = {
      enable = true;
      config = {
        Label = "dev.herdr.hail";
        ProgramArguments = hail.launchPrefix ++ [ (lib.getExe hail.package) ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 900;
        ProcessType = "Background";
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          HERDR_SOCKET_PATH = "${config.xdg.configHome}/herdr/herdr.sock";
          HERDR_PLUGIN_CONFIG_DIR = "${configStoreDir}/herdr-hail-config";

          # launchd supplies no Nix profile; keep a runtime wrapper available.
          PATH = lib.concatStringsSep ":" [
            "${config.home.homeDirectory}/.nix-profile/bin"
            "/etc/profiles/per-user/${config.home.username}/bin"
            "/run/current-system/sw/bin"
            "/nix/var/nix/profiles/default/bin"
            "/usr/local/bin"
            "/usr/bin"
            "/bin"
            "/usr/sbin"
            "/sbin"
          ];
        };
        StandardOutPath = "${logDir}/hail.log";
        StandardErrorPath = "${logDir}/hail.error.log";
      };
    };
  };
}
