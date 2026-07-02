#
# Open WebUI Module — package + optional LaunchAgent (chat UI server)
#
# The package is always installed (CLI available for ad-hoc use). The
# LaunchAgent is opt-in via programs.open-webui.enable: it runs
# `open-webui serve` bound to loopback as the manual-query chat UI for the
# local OpenAI-compatible inference endpoint (llama-swap on :11434). LAN
# exposure, TLS, and access control are the consumer's concern (e.g. a
# reverse proxy in front) — this module never binds beyond cfg.host.
#
# Endpoints (when running):
#   - http://127.0.0.1:8080/  — chat UI (Open WebUI keeps its own login/auth)
#
# Logs: ~/Library/Logs/open-webui/open-webui.{log,error.log}
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.open-webui;
in
{
  options.programs.open-webui = {
    enable = lib.mkEnableOption "Open WebUI LaunchAgent (dev.open-webui.server)";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address. Keep loopback; front with a reverse proxy for any off-host access.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Listen port (8080 is reserved for Open WebUI in the local port map).";
    };

    openaiApiBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11434/v1";
      description = "OpenAI-compatible upstream the UI queries (llama-swap proxy by default).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/open-webui";
      description = "Persistent state (SQLite DB, uploads, vector cache).";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables merged into the LaunchAgent (host-specific tuning, feature flags).";
    };
  };

  config = lib.mkMerge [
    { home.packages = [ pkgs.open-webui ]; }

    (lib.mkIf cfg.enable {
      launchd.agents.open-webui = {
        enable = true;
        config = {
          Label = "dev.open-webui.server";
          ProgramArguments = [
            (lib.getExe pkgs.open-webui)
            "serve"
            "--host"
            cfg.host
            "--port"
            (toString cfg.port)
          ];
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 30;
          ProcessType = "Background";
          # Without a WorkingDirectory launchd spawns at "/" and Open WebUI
          # crash-loops writing its relative-path secret key there
          # ("Read-only file system: '/.webui_secret_key'", jevans-ms
          # 2026-07-02). Pin both the cwd and the key file into dataDir.
          WorkingDirectory = cfg.dataDir;
          EnvironmentVariables = {
            HOME = config.home.homeDirectory;
            DATA_DIR = cfg.dataDir;
            WEBUI_SECRET_KEY_FILE = "${cfg.dataDir}/.webui_secret_key";
            OPENAI_API_BASE_URL = cfg.openaiApiBaseUrl;
            # The local llama-swap endpoint is unauthenticated on loopback but
            # Open WebUI requires a non-empty key when the OpenAI API is on.
            OPENAI_API_KEY = "local";
            # llama-swap speaks the OpenAI surface, not the Ollama native API
            # — leaving this on makes the UI poll /api/tags and log errors.
            ENABLE_OLLAMA_API = "False";
            # No phone-home from an autonomous server.
            SCARF_NO_ANALYTICS = "true";
            DO_NOT_TRACK = "true";
            ANONYMIZED_TELEMETRY = "false";
          }
          // cfg.environment;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/open-webui/open-webui.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/open-webui/open-webui.error.log";
        };
      };

      # launchd does not create StandardOutPath/StandardErrorPath parent
      # directories, and a missing WorkingDirectory prevents the agent from
      # spawning at all — create both up front on fresh hosts.
      home.activation.createOpenWebuiLogDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p "${config.home.homeDirectory}/Library/Logs/open-webui" "${cfg.dataDir}"
      '';

      # Log rotation via newsyslog (follows mlx/launchd.nix pattern)
      home.file.".config/newsyslog.d/open-webui.conf".text = ''
        # logfilename                                                              [owner:group]  mode  count  size  when  flags
        ${config.home.homeDirectory}/Library/Logs/open-webui/open-webui.error.log :              644   3      10240 *     J
        ${config.home.homeDirectory}/Library/Logs/open-webui/open-webui.log       :              644   3      10240 *     J
      '';

      launchd.agents.open-webui-logrotate = {
        enable = true;
        config = {
          Label = "dev.open-webui.logrotate";
          ProgramArguments = [
            "/usr/sbin/newsyslog"
            "-f"
            "${config.home.homeDirectory}/.config/newsyslog.d/open-webui.conf"
          ];
          StartCalendarInterval = [ { Minute = 0; } ]; # hourly
        };
      };
    })
  ];
}
