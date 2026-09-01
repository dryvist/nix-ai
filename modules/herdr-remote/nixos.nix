# herdr-remote — NixOS service module. Exported as nixosModules.herdr-remote.
#
# The relay and web dashboard half of herdr: live agent timelines, one-tap
# approvals, terminal interaction from a browser or phone.
#
# It holds NO agent state and never touches herdr's control socket. It drives
# each runtime over SSH, named in HERDR_REMOTES, so this guest is disposable —
# the opposite of the runtime guest, whose /var/lib/herdr is the one path in
# the estate worth backing up.
{
  config,
  lib,
  pkgs,
  herdr-remote-src,
  ...
}:

let
  cfg = config.services.herdr-remote;
  stateDirName = lib.removePrefix "/var/lib/" cfg.stateDir;
  loopback = [
    "127.0.0.1"
    "localhost"
    "::1"
  ];
in
{
  options.services.herdr-remote = {
    enable = lib.mkEnableOption "the herdr-remote relay and web dashboard";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { src = herdr-remote-src; };
      defaultText = lib.literalExpression "the pinned herdr-remote relay";
      description = "herdr-remote relay package to run.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "herdr-remote";
      description = "User the relay runs as.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/herdr-remote";
      description = "Home, log and push-subscription directory. Rebuildable; not worth backing up.";
    };

    bindHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address the relay's WebSocket binds. Left on loopback by default: this
        guest sits behind the estate's Traefik ingress and the Authelia gate,
        so the relay itself never needs to be reachable directly.
      '';
    };

    bindPort = lib.mkOption {
      type = lib.types.port;
      default = 8375;
      description = ''
        WebSocket port. 8375 is upstream's default and is the value
        tofu-proxmox pins as `herdr_relay_ws` for the ingress route; changing
        it here alone produces a route to a closed port.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/var/lib/herdr-remote/.env";
      description = ''
        systemd EnvironmentFile carrying HERDR_RELAY_TOKEN, HERDR_REMOTES and
        the VAPID push keys. Written out of band at 0600; never in the Nix
        store, which is world-readable. Loaded with a leading `-`, so a missing
        file leaves the unit inert rather than crash-looping.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "/var/lib/" cfg.stateDir;
        message = "services.herdr-remote.stateDir must be under /var/lib, because systemd's StateDirectory is relative to it.";
      }
      {
        # Upstream refuses to start when RELAY_HOST is non-loopback with no
        # AUTH_TOKEN (herdr_relay.py raises SystemExit). Nix cannot check the
        # token itself — it lives in environmentFile, read at runtime — so this
        # asserts the one half that IS visible at build time: a non-loopback
        # bind must at least have a file that could carry the token. Necessary,
        # not sufficient. The sufficient check is upstream's own refusal.
        #
        # Deliberately NOT written as `<cond> -> true`, which is a tautology
        # that reads like a guard and can never fire.
        assertion = builtins.elem cfg.bindHost loopback || cfg.environmentFile != null;
        message = ''
          services.herdr-remote.bindHost is ${cfg.bindHost}, which is not
          loopback, but no environmentFile is set — so HERDR_RELAY_TOKEN cannot
          reach the unit and upstream will refuse to start. Set an
          environmentFile carrying the token, or bind loopback and let the
          ingress terminate.
        '';
      }
    ];

    users = {
      groups.${cfg.user} = { };
      users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.user;
        home = cfg.stateDir;
        createHome = true;
      };
    };

    systemd.services.herdr-remote = {
      description = "herdr-remote relay and web dashboard";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe cfg.package;
        User = cfg.user;
        Group = cfg.user;
        WorkingDirectory = cfg.stateDir;
        StateDirectory = stateDirName;
        # Holds HERDR_RELAY_TOKEN-authenticated push subscriptions and agent
        # transcripts read off the runtimes. Same 0700 as the runtime guest.
        StateDirectoryMode = "0700";
        Restart = "always";
        RestartSec = "5s";
      }
      // lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = "-${cfg.environmentFile}";
      };

      unitConfig = {
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      };

      environment = {
        HOME = cfg.stateDir;
        HERDR_RELAY_HOST = cfg.bindHost;
        HERDR_RELAY_PORT = toString cfg.bindPort;
        HERDR_LOG_DIR = cfg.stateDir;
      };
    };
  };
}
