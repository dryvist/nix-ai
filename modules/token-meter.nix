# splunk/token-meter — local Claude Code / Codex token usage dashboard.
#
# Upstream installs entirely user-space via its own ./scripts/install, which
# writes and owns two LaunchAgents (server + menu bar). This module only
# clones/updates the checkout, runs that installer, and optionally fronts the
# hardcoded 127.0.0.1:8722 dashboard with a Caddy HTTPS gate for LAN access.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.token-meter;
  supportDir = "${config.home.homeDirectory}/Library/Application Support/Token Meter";
  logDir = "${config.home.homeDirectory}/Library/Logs/token-meter";

  caddyfile = pkgs.writeText "token-meter-Caddyfile" ''
    ${cfg.bindAddress}:${toString cfg.gatePort} {
      bind ${cfg.bindAddress}
      tls internal
      reverse_proxy 127.0.0.1:8722
    }
  '';
in
{
  options.programs.token-meter = {
    enable = lib.mkEnableOption "splunk/token-meter usage dashboard";

    repo = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/splunk/token-meter.git";
      description = "Upstream repository; tracks its default branch (no pinned rev).";
    };

    installDir = lib.mkOption {
      type = lib.types.str;
      default = "${supportDir}/source";
      description = ''
        Git checkout the installer runs from. The default matches upstream's own
        MANAGED_SOURCE_ROOT, so its self-updater and this module share one
        checkout instead of upstream cloning a second one alongside.
      '';
    };

    menuBar = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Keep the menu bar agent. Upstream's installer has no flag to skip it and
        aborts if it fails to register, so `false` boots it out afterwards.
      '';
    };

    httpsGate.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Front the loopback dashboard with a self-signed HTTPS reverse proxy.";
    };

    gatePort = lib.mkOption {
      type = lib.types.port;
      default = 8723;
      description = "Port for the HTTPS gate; 8722 belongs to token-meter itself.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "LAN address the HTTPS gate binds to. Required when the gate is enabled.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.httpsGate.enable || cfg.bindAddress != "";
        message = "programs.token-meter.bindAddress must be set when httpsGate.enable is true — an empty value would expose the dashboard on every interface.";
      }
    ];

    home.activation.tokenMeter = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      export PATH="${lib.makeBinPath [ pkgs.git ]}:/usr/bin:/bin:$PATH"
      src="${cfg.installDir}"

      $DRY_RUN_CMD mkdir -p "${logDir}"

      if [ -d "$src/.git" ]; then
        $DRY_RUN_CMD git -C "$src" pull --quiet --ff-only \
          || echo "token-meter: could not fast-forward $src" >&2
      else
        $DRY_RUN_CMD git clone --quiet "${cfg.repo}" "$src" \
          || echo "token-meter: clone failed" >&2
      fi

      # Upstream's installer waits on a health check for up to 600s and exits
      # non-zero on any failure, so run it only when the checkout moved and
      # never let it abort the rest of the activation.
      head=$(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo unknown)
      if [ "$head" != "$(cat "${supportDir}/runtime/INSTALLED_REVISION" 2>/dev/null || true)" ]; then
        $DRY_RUN_CMD "$src/scripts/install" \
          || echo "token-meter: scripts/install failed (it needs Xcode CLT swiftc)" >&2
      fi
      ${lib.optionalString (!cfg.menuBar) ''
        $DRY_RUN_CMD launchctl bootout "gui/$(id -u)/com.token-meter.menubar" 2>/dev/null || true
        $DRY_RUN_CMD rm -f "$HOME/Library/LaunchAgents/com.token-meter.menubar.plist"
      ''}
    '';

    launchd.agents.token-meter-gate = lib.mkIf cfg.httpsGate.enable {
      enable = true;
      config = {
        Label = "dev.token-meter.gate";
        ProgramArguments = [
          (lib.getExe pkgs.caddy)
          "run"
          "--config"
          "${caddyfile}"
          "--adapter"
          "caddyfile"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        ProcessType = "Background";
        EnvironmentVariables.HOME = config.home.homeDirectory;
        StandardOutPath = "${logDir}/gate.log";
        StandardErrorPath = "${logDir}/gate.error.log";
      };
    };
  };
}
