#
# herdr Module — LaunchAgent (headless server)
#
# The TUI is a client; without this server nothing manages panes and every
# agent-control subcommand has nothing to talk to.
#
# The interpreter convention in modules/mlx/options-launch.nix does not apply:
# it governs shell-SCRIPT agents. herdr is a binary doing its own network work,
# so it is its own responsible process for TCC and needs a stable code-signing
# identity rather than an Apple interpreter.
#
{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.herdr;
  logDir = "${config.home.homeDirectory}/Library/Logs/herdr";
in
{
  config = lib.mkIf (cfg.enable && cfg.package != null) {
    launchd.agents.herdr = {
      enable = true;
      config = {
        Label = "dev.herdr.server";
        ProgramArguments = [
          (lib.getExe cfg.package)
          "server"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        ProcessType = "Background";
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;

          # The only variable that moves the control socket, and it must match
          # what the interactive client resolves. A mismatch leaves the client
          # hunting a socket nothing created — silent, not an error.
          HERDR_SOCKET_PATH = "${config.home.homeDirectory}/${cfg.configDir}/herdr.sock";

          # Panes inherit this PATH, so it is what agent CLIs are found on.
          # launchd supplies no Nix profile; without one every pane is a shell
          # that cannot run claude or codex, which herdr reports as a bare
          # shell rather than as an error.
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
        StandardOutPath = "${logDir}/herdr.log";
        StandardErrorPath = "${logDir}/herdr.error.log";
      };
    };
  };
}
