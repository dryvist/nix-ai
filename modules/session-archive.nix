# Daily push of AI session history to S3-compatible vendor buckets (RustFS).
#
# Complements session-sync's Mac-to-Mac push: this is the off-Mac copy, one
# bucket per vendor tool, credentials minted per run from OpenBao via doppler.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.sessionArchive;
  logDir = "${config.home.homeDirectory}/Library/Logs/session-archive";
  scriptArgs = lib.escapeShellArgs (
    [
      (lib.getExe' pkgs.awscli2 "aws")
      logDir
      "${config.home.homeDirectory}/Library/Caches/session-archive.lock"
      cfg.endpoint
      "--vendors"
    ]
    ++ lib.mapAttrsToList (dir: bucket: "${dir}=${bucket}") cfg.vendors
    ++ [ "--excludes" ]
    ++ cfg.excludes
  );
in
{
  options.programs.sessionArchive = {
    enable = lib.mkEnableOption "daily push of AI session history to S3-compatible vendor buckets";

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "S3 endpoint URL. Required when enabled.";
    };

    vendors = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        ".claude" = "ai-sessions-claude";
        ".codex" = "ai-sessions-codex";
        ".gemini" = "ai-sessions-gemini";
        ".antigravity" = "ai-sessions-gemini";
      };
      description = "Home-relative directory -> bucket name.";
    };

    excludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # aws-cli --exclude globs. The bare-prefix AND */ forms are BOTH
        # required: the */name/* form alone does not match top-level dirs
        # (a real bug, not belt-and-braces).
        "plugins/*"
        "*/plugins/*"
        "security/*"
        "*/security/*"
        ".tmp/*"
        "*/.tmp/*"
        # Credentials must never leave the machine as a side effect of backup.
        "*.credentials.json"
        "*auth.json"
        "*oauth_creds.json"
        "*antigravity-oauth-token"
        "*.DS_Store"
      ];
      description = "aws s3 sync --exclude patterns, applied to every vendor dir.";
    };

    calendarHour = lib.mkOption {
      type = lib.types.int;
      # 03:41 — deliberately off the :00/:30 marks every other job clusters on.
      default = 3;
      description = "Hour of the daily run.";
    };

    calendarMinute = lib.mkOption {
      type = lib.types.int;
      default = 41;
      description = "Minute of the daily run.";
    };

    dopplerBin = lib.mkOption {
      type = lib.types.str;
      default = "doppler";
      description = "doppler binary; resolved via the agent's PATH because doppler auth is user-level.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.endpoint != "";
        message = "programs.sessionArchive.endpoint must name the S3 endpoint to push to.";
      }
    ];

    launchd.agents.session-archive = {
      enable = true;
      config = {
        Label = "dev.session-archive";
        # wait4path: the agent can fire before /nix/store is mounted after boot.
        # doppler injects the OpenBao AppRole env the script authenticates with.
        ProgramArguments = [
          "/bin/sh"
          "-c"
          "/bin/wait4path /nix/store && exec ${lib.escapeShellArg cfg.dopplerBin} run -p iac-conf-mgmt -c prd -- ${./scripts/session-archive.sh} ${scriptArgs}"
        ];
        StartCalendarInterval = [
          {
            Hour = cfg.calendarHour;
            Minute = cfg.calendarMinute;
          }
        ];
        RunAtLoad = false;
        ProcessType = "Background";
        LowPriorityIO = true;
        Nice = 10;
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          # Same PATH shape as the maestro agent: per-user profile first so the
          # user-level doppler install resolves, then system and Apple paths.
          PATH = "${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/bin:/bin";
        };
        StandardOutPath = "${logDir}/agent.log";
        StandardErrorPath = "${logDir}/agent.error.log";
      };
    };
  };
}
