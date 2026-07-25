#
# Fabric Module — LaunchAgent (REST API Server)
#
# Runs `fabric --serve` as a macOS LaunchAgent, exposing fabric's REST API
# and Swagger UI on the configured port (default 8180).
#
# Only active when both `programs.fabric.enable` AND `programs.fabric.enableServer`
# are true. The CLI works without the server — this is only needed for programmatic
# REST access and the Swagger UI.
#
# Endpoints (when running):
#   - http://127.0.0.1:8180/                          — REST API
#   - http://127.0.0.1:8180/swagger/index.html        — Swagger UI
#
# Logs: ~/Library/Logs/fabric/fabric.{log,error.log}
#
{
  config,
  lib,
  fabricShared,
  ...
}:
let
  inherit (fabricShared) cfg fabricPkg;
in
{
  config = lib.mkIf (cfg.enable && cfg.enableServer) {
    launchd.agents.fabric = {
      enable = true;
      config = {
        Label = "dev.fabric.server";
        ProgramArguments = [
          (lib.getExe fabricPkg)
          "--serve"
          "--address"
          "${cfg.host}:${toString cfg.port}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        # Throttle restarts to avoid crash-loop scenarios
        ThrottleInterval = 30;
        ProcessType = "Background";
        EnvironmentVariables = {
          FABRIC_PATTERNS_DIR = cfg.patternsDir;
          HOME = config.home.homeDirectory;
        };
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/fabric/fabric.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/fabric/fabric.error.log";
      };
    };

    # Rotation for ~/Library/Logs/fabric lives in nix-darwin's
    # programs.agent-log-rotation, run by the system newsyslog as root. This
    # module used to copy mlx/launchd.nix's user LaunchAgent, which could never
    # work: newsyslog refuses to run as anyone but root.
  };
}
