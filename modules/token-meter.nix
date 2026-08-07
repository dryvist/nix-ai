# splunk/token-meter — local Claude Code / Codex token usage dashboard.
#
# Upstream installs entirely user-space via its own ./scripts/install, which
# writes and owns two LaunchAgents (server + menu bar). This module only
# clones/updates the checkout, runs that installer, and optionally fronts the
# loopback dashboard with a Caddy HTTPS gate for LAN access.
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
  gateStateDir = "${config.home.homeDirectory}/.local/share/token-meter-gate";

  # `auto_https disable_redirects` is load-bearing, not tidiness: by default
  # Caddy also opens a redirect listener on port 80 to send http:// callers to
  # https://. This runs as a user LaunchAgent, which cannot bind a privileged
  # port, and Caddy treats the failed bind as fatal — so the entire config
  # fails to load and the gate serves nothing at all. The redirect buys nothing
  # here anyway; the only advertised URL is the https one on gatePort.
  #
  # Body indented with tabs because that is what `caddy fmt` emits; spaces make
  # Caddy log an "input is not formatted" warning on every start.
  caddyfile = pkgs.writeText "token-meter-Caddyfile" ''
    {
    	auto_https disable_redirects
    }

    ${cfg.bindAddress}:${toString cfg.gatePort} {
    	bind ${cfg.bindAddress}
    	tls internal
    	reverse_proxy 127.0.0.1:${toString cfg.dashboardPort}
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

    httpsGate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Front the loopback dashboard with a self-signed HTTPS reverse proxy.";
    };

    dashboardPort = lib.mkOption {
      type = lib.types.port;
      default = 8722;
      description = ''
        Loopback port token-meter's own server listens on. Upstream hardcodes
        this, so changing it only makes sense alongside a patched install —
        it exists so the gate and its check derive the value instead of each
        restating it.
      '';
    };

    gatePort = lib.mkOption {
      type = lib.types.port;
      default = 8723;
      description = "Port for the HTTPS gate. Must differ from dashboardPort.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "LAN address the HTTPS gate binds to. Required when the gate is enabled.";
    };
  };

  config = lib.mkMerge [
    # Turning the option off has to actually turn the thing off; see the
    # script's own header for why a rebuild cannot do it on its own.
    (lib.mkIf (!cfg.enable) {
      home.activation.tokenMeterCleanup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD ${./scripts/token-meter-cleanup.sh}
      '';
    })

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !cfg.httpsGate || cfg.bindAddress != "";
          message = "programs.token-meter.bindAddress must be set when httpsGate is true — an empty value would expose the dashboard on every interface.";
        }
        {
          assertion = !cfg.httpsGate || cfg.gatePort != cfg.dashboardPort;
          message = "programs.token-meter.gatePort must differ from dashboardPort — equal ports make the gate proxy to itself.";
        }
      ];

      home.activation.tokenMeter = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        PATH="${lib.makeBinPath [ pkgs.git ]}:/usr/bin:/bin:$PATH" $DRY_RUN_CMD ${./scripts/token-meter-install.sh} \
          ${
            lib.escapeShellArgs [
              cfg.repo
              cfg.installDir
              "${supportDir}/.nix-install-stamp"
              logDir
            ]
          } ${if cfg.menuBar then "1" else "0"}
      '';

      launchd.agents.token-meter-gate = lib.mkIf cfg.httpsGate {
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
            HOME = config.home.homeDirectory;
            # Give this Caddy its own storage. A host running the gate is a host
            # already running the llm-gate Caddy, and on the default paths both
            # would share one data directory — including its local CA, its
            # instance id, and its lock files. llm-gate isolates itself the same
            # way, so matching it keeps the two from contending over state that
            # is not designed to have two owners.
            XDG_CONFIG_HOME = "${gateStateDir}/config";
            XDG_DATA_HOME = "${gateStateDir}/data";
          };
          StandardOutPath = "${logDir}/gate.log";
          StandardErrorPath = "${logDir}/gate.error.log";
        };
      };

      # The catalog ships this entry disabled because it needs the local install
      # that only this module performs — so the module enabling itself is exactly
      # the condition that makes it usable. Without this, `enable = true` installs
      # the dashboard but every agent's MCP config silently omits the server,
      # since enabledServers filters `disabled` entries out.
      programs.aiMcp.servers.token-meter.disabled = lib.mkForce false;
    })
  ];
}
