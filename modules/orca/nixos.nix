# orca-server NixOS service module.
#
# Runs the headless Orca server (`orca serve`) as the `orca-server` system
# unit. When services.herdr is enabled the unit runs as herdr's user and home
# and gets herdr's agent CLIs on PATH; otherwise it creates a dedicated `orca`
# system user whose home is stateDir. Exported as nixosModules.orca-server.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.orca-server;

  # The herdr module is optional. Test for its option before reading it.
  herdrEnabled = (config.services ? herdr) && config.services.herdr.enable;
in
{
  options.services.orca-server = {
    enable = lib.mkEnableOption "the headless Orca server (orca serve)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./server-package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./server-package.nix { }";
      description = "Orca server package to run.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = if herdrEnabled then config.services.herdr.user else "orca";
      defaultText = lib.literalExpression ''if services.herdr.enable then services.herdr.user else "orca"'';
      description = ''
        User the server runs as. The default `orca` user is created by this
        module; any other value must already exist.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = if herdrEnabled then config.services.herdr.stateDir else "/var/lib/orca";
      defaultText = lib.literalExpression ''if services.herdr.enable then services.herdr.stateDir else "/var/lib/orca"'';
      description = "Home and working directory of the server user.";
    };

    bind = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = ''
        Address the server listens on, passed as `--bind`. The CLI default is
        127.0.0.1; this default listens on every interface. Clients from public
        addresses are refused unless the CLI's `--allow-public` is given, which
        this module does not pass.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6768;
      description = "TCP port the server listens on. Opened in the firewall.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional tools the server's sessions need on PATH.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users = lib.mkIf (cfg.user == "orca") {
      orca = {
        isSystemUser = true;
        group = "orca";
        home = cfg.stateDir;
        createHome = true;
      };
    };

    users.groups = lib.mkIf (cfg.user == "orca") { orca = { }; };

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # Puts `orca` on the PATH of interactive sessions, for one-time foreground
    # runs as the server user.
    environment.systemPackages = [ cfg.package ];

    systemd.services.orca-server = {
      description = "Orca headless server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # The launcher is a shell script that uses coreutils. Agent CLIs are the
      # same set the herdr unit puts on its PATH.
      path = [
        pkgs.coreutils
        pkgs.git
      ]
      ++ lib.optionals herdrEnabled config.services.herdr.agentPackages
      ++ cfg.extraPackages;

      environment = {
        HOME = cfg.stateDir;
        ORCA_TELEMETRY_DISABLED = "1";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/orca serve --supervise --no-pairing --bind ${cfg.bind} --port ${toString cfg.port}";
        User = cfg.user;
        Group = cfg.user;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
