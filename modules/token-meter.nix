{
  config,
  lib,
  pkgs,
  token-meter-src,
  ...
}:

let
  cfg = config.programs.token-meter;
  homeDir = config.home.homeDirectory;
  logDir = "${homeDir}/Library/Logs/token-meter";
  gateStateDir = "${homeDir}/.local/share/token-meter-gate";
  packages = import ./token-meter/package.nix {
    inherit lib pkgs token-meter-src;
  };
  runtimeRoot = "${packages.runtime}/share/token-meter";
  settingsJson = pkgs.writeText "token-meter-settings.json" (
    builtins.toJSON {
      updates = {
        enabled = false;
        auto_install = false;
      };
    }
  );
  siteHost = if cfg.siteHostName != "" then cfg.siteHostName else cfg.bindAddress;
  caddyfile = pkgs.writeText "token-meter-Caddyfile" ''
    {
    	auto_https disable_redirects
    }

    ${siteHost}:${toString cfg.gatePort} {
    	bind ${cfg.bindAddress}
    	tls internal
    	reverse_proxy 127.0.0.1:${toString cfg.dashboardPort}
    }
  '';
in
{
  imports = [
    (lib.mkChangedOptionModule
      [
        "programs"
        "token-meter"
        "enable"
      ]
      [
        "programs"
        "token-meter"
        "disabled"
      ]
      (legacyConfig: !legacyConfig.programs.token-meter.enable)
    )
    (lib.mkRemovedOptionModule [ "programs" "token-meter" "repo" ] ''
      Token Meter source is now pinned by the token-meter-src flake input.
    '')
    (lib.mkRemovedOptionModule [ "programs" "token-meter" "installDir" ] ''
      Token Meter runtime files are now immutable Nix store paths. Application
      settings and databases remain writable under ~/.token-meter.
    '')
  ];

  options.programs.token-meter = {
    disabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to disable the splunk/token-meter usage dashboard.";
    };

    menuBar = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to run Token Meter's macOS menu-bar companion.";
    };

    httpsGate = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to front the loopback dashboard with a self-signed HTTPS reverse proxy.";
    };

    dashboardPort = lib.mkOption {
      type = lib.types.port;
      default = 8722;
      description = "Loopback port used by Token Meter's server.";
    };

    siteHostName = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "host.example.com";
      description = "Hostname covered by the HTTPS gate certificate; empty reuses bindAddress.";
    };

    gatePort = lib.mkOption {
      type = lib.types.port;
      default = 8723;
      description = "Port for the HTTPS gate.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "LAN address for the optional HTTPS gate.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.disabled {
      home.activation.cleanupLegacyTokenMeter = lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
        $DRY_RUN_CMD ${lib.getExe pkgs.bash} ${./scripts/cleanup-token-meter-launch-agents.sh} ${lib.escapeShellArg homeDir}
      '';
    })

    (lib.mkIf (!cfg.disabled) {
      assertions = [
        {
          assertion = !cfg.httpsGate || cfg.bindAddress != "";
          message = "programs.token-meter.bindAddress must be set when httpsGate is true.";
        }
        {
          assertion = !cfg.httpsGate || cfg.gatePort != cfg.dashboardPort;
          message = "programs.token-meter.gatePort must differ from dashboardPort.";
        }
      ];

      home.activation.tokenMeterSettings = lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
        $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg logDir}
        export PATH="${pkgs.jq}/bin:$PATH"
        $DRY_RUN_CMD ${./scripts/merge-json-settings.sh} \
          ${settingsJson} \
          ${lib.escapeShellArg "${homeDir}/.token-meter/settings.json"}
      '';

      launchd.agents = {
        token-meter-server = {
          enable = true;
          config = {
            Label = "com.token-meter.server";
            ProgramArguments = [ "${packages.runtime}/bin/token-meter-server" ];
            WorkingDirectory = runtimeRoot;
            RunAtLoad = true;
            KeepAlive = true;
            ThrottleInterval = 5;
            ProcessType = "Background";
            EnvironmentVariables.HOME = homeDir;
            StandardOutPath = "${logDir}/meter.log";
            StandardErrorPath = "${logDir}/meter.err.log";
          };
        };

        token-meter-menubar = lib.mkIf cfg.menuBar {
          enable = true;
          config = {
            Label = "com.token-meter.menubar";
            ProgramArguments = [
              "${packages.menuBar}/Applications/Token Meter Menu Bar.app/Contents/MacOS/token-meter-menubar"
            ];
            WorkingDirectory = runtimeRoot;
            RunAtLoad = true;
            KeepAlive.SuccessfulExit = false;
            ThrottleInterval = 5;
            EnvironmentVariables.HOME = homeDir;
            StandardOutPath = "${logDir}/menubar.log";
            StandardErrorPath = "${logDir}/menubar.err.log";
          };
        };

        token-meter-gate = lib.mkIf cfg.httpsGate {
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
            EnvironmentVariables = {
              HOME = homeDir;
              XDG_CONFIG_HOME = "${gateStateDir}/config";
              XDG_DATA_HOME = "${gateStateDir}/data";
            };
            StandardOutPath = "${logDir}/gate.log";
            StandardErrorPath = "${logDir}/gate.error.log";
          };
        };
      };

      programs.aiMcp.servers.token-meter = {
        command = "${packages.runtime}/bin/token-meter-mcp";
        clientNameEnv = "TOKEN_METER_CALLER";
        disabled = false;
      };
    })
  ];
}
