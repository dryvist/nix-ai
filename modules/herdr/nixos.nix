# herdr — NixOS service module
#
# The server half of modules/herdr/. Exported as nixosModules.herdr.
#
# herdr's own docs describe a user-session daemon you attach to from a terminal.
# On a single-purpose guest a system service running as a dedicated user is more
# deterministic — no lingering, no login session to lose — and it buys the thing
# the rest of this design needs: a STABLE SOCKET PATH. RuntimeDirectory pins it
# at /run/herdr, so the Slack bridge can forward it over SSH from its own
# container (`ssh -L /run/herdr/herdr.sock:/run/herdr/herdr.sock`) instead of
# guessing at $XDG_RUNTIME_DIR/<uid>.
{
  config,
  lib,
  pkgs,
  llm-agents,
  ...
}:

let
  cfg = config.services.herdr;
  agents = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.services.herdr = {
    enable = lib.mkEnableOption "the herdr agent-multiplexer server";

    package = lib.mkOption {
      type = lib.types.package;
      default = agents.herdr;
      defaultText = lib.literalExpression "llm-agents.packages.\${system}.herdr";
      description = "herdr package to run.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "herdr";
      description = "User the herdr server and every agent pane runs as.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/herdr";
      description = ''
        Home and state directory. This is the ONLY path on the guest worth
        backing up: agent credentials, git worktrees, and session state all
        live here. Everything else rebuilds from the flake.
      '';
    };

    agentPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [
        agents.claude-code
        agents.antigravity-cli
        agents.copilot-cli
        pkgs.codex
        pkgs.opencode
        pkgs.qwen-code
      ];
      defaultText = lib.literalExpression "the freely-licensed AI CLIs this flake manages";
      description = ''
        The agent CLIs herdr can start in a pane. Same source as the
        home-manager module uses on the workstation, so a pane on the server
        runs the same build as a pane on the Mac.

        Every default is freely licensed, so enabling this service evaluates on
        a stock host. `cursor-cli` is deliberately NOT here: it is unfree, and
        an unfree default makes `services.herdr.enable = true` fail at
        evaluation on any host that has not opted in — naming a package the
        operator never asked for. Add it through `extraPackages` alongside the
        host's own unfree opt-in.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional tools the agents need on PATH (git, ripgrep, language toolchains).";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/var/lib/herdr/.env";
      description = ''
        systemd EnvironmentFile holding the per-guest secrets NixOS cannot know
        — API keys, router endpoint, Slack tokens. Written out of band at mode
        0600; never rendered into the Nix store, which is world-readable.
        Loaded with a leading `-`, so a missing file leaves the service inert
        rather than failing to start.
      '';
    };

    onFailureUnit = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "herdr-unit-alert@%n.service";
      description = "Unit to trigger via OnFailure=, mirroring the fleet's hermes-unit-alert pattern.";
    };
  };

  config = lib.mkIf cfg.enable {
    users = {
      groups.${cfg.user} = { };

      users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.user;
        home = cfg.stateDir;
        createHome = true;
        # A real shell, deliberately: herdr's whole job is to run interactive
        # agent CLIs in PTYs. The guest is the blast-radius boundary, the same
        # reasoning the fleet's hermes and agent-exec users are documented with.
        shell = pkgs.bashInteractive;
      };
    };

    environment.systemPackages = [ cfg.package ] ++ cfg.agentPackages ++ cfg.extraPackages;

    systemd.services.herdr = {
      description = "herdr agent multiplexer server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      path = [ cfg.package ] ++ cfg.agentPackages ++ cfg.extraPackages;

      unitConfig = {
        # In [Unit], not [Service]. systemd moved these and silently ignores
        # them in the wrong section — the same trap hermes-gateway.service
        # documents.
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      }
      // lib.optionalAttrs (cfg.onFailureUnit != null) { OnFailure = cfg.onFailureUnit; };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/herdr server";
        ExecStop = "${cfg.package}/bin/herdr server stop";
        User = cfg.user;
        Group = cfg.user;
        WorkingDirectory = cfg.stateDir;
        StateDirectory = "herdr";
        # Pins the control socket at /run/herdr instead of a uid-derived
        # $XDG_RUNTIME_DIR path, so remote bridges can forward a known path.
        RuntimeDirectory = "herdr";
        RuntimeDirectoryMode = "0750";
        Restart = "always";
        RestartSec = "5s";
      }
      // lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = "-${cfg.environmentFile}";
      };

      environment = {
        HOME = cfg.stateDir;
        XDG_RUNTIME_DIR = "/run/herdr";
      };
    };
  };
}
