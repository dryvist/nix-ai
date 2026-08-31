# herdr — NixOS service module
#
# The server half of modules/herdr/. Exported as nixosModules.herdr.
#
# herdr's own docs describe a user-session daemon you attach to from a terminal.
# On a single-purpose guest a system service running as a dedicated user is more
# deterministic — no lingering, no login session to lose — and it buys the thing
# the rest of this design needs: a STABLE SOCKET PATH, so a remote client can
# reach the socket at a known location rather than discovering it.
#
# That path is pinned by HERDR_SOCKET_PATH, NOT by RuntimeDirectory alone.
# Verified against herdr 0.8.2: the default socket is derived from the CONFIG
# directory (`herdr status` reports ~/.config/herdr/herdr.sock), and
# XDG_RUNTIME_DIR appears exactly once in the binary, in unrelated
# pane-graphics path validation. Setting only RuntimeDirectory would leave
# /run/herdr empty and put the real socket under ${stateDir}/.config, so the
# forward above would forward nothing.
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

  # Bound once: systemd creates /run/${runtimeDirName} from RuntimeDirectory,
  # and herdr is told to listen inside it. Two literals would drift silently.
  runtimeDirName = "herdr";
  runtimeDir = "/run/${runtimeDirName}";
  socketPath = "${runtimeDir}/herdr.sock";

  # systemd's StateDirectory is always relative to /var/lib, so it has to be
  # derived from stateDir rather than hardcoded -- otherwise overriding
  # stateDir leaves systemd managing an unused /var/lib/herdr while the real
  # directory gets none of its ownership or mode handling.
  stateDirName = lib.removePrefix "/var/lib/" cfg.stateDir;
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
      defaultText = lib.literalExpression "the AI CLIs this flake manages that evaluate without allowUnfree";
      description = ''
        The agent CLIs herdr can start in a pane. Same source as the
        home-manager module uses on the workstation, so a pane on the server
        runs the same build as a pane on the Mac.

        Every default evaluates on a stock host, so enabling this service does
        not require an unfree opt-in. `cursor-cli` is deliberately NOT here: it
        is gated unfree, and an unfree default makes `services.herdr.enable =
        true` fail at evaluation on any host that has not opted in — naming a
        package the operator never asked for. Add it through `extraPackages`
        alongside the host's own unfree opt-in.

        "Evaluates on a stock host" is not the same as "freely licensed", and
        the difference is load-bearing. Claude Code, Antigravity CLI and Copilot
        CLI are proprietary: their `meta.license` carries
        `shortName = "unfree"` and `redistributable = false`, but also
        `free = true`, so nixpkgs derives `meta.unfree = false` and never gates
        them. If that upstream declaration is ever corrected, three of these
        defaults start failing evaluation at once, and the breakage will look
        unrelated to herdr.
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
    assertions = [
      {
        assertion = lib.hasPrefix "/var/lib/" cfg.stateDir;
        message = "services.herdr.stateDir must be under /var/lib, because systemd's StateDirectory is relative to it.";
      }
    ];

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

    # Only the herdr CLI is installed system-wide, so an operator can attach.
    # The agent CLIs reach the service through the unit's own `path` below;
    # putting them in systemPackages would install every one of them for every
    # user on the host and pull them into the system closure.
    environment.systemPackages = [ cfg.package ];

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
        StateDirectory = stateDirName;
        # systemd applies this to the directory on every start, overriding the
        # 0700 that createHome produces, and its own default is laxer than that.
        # This directory holds agent credentials, so pin it to the same 0700 the
        # nixpkgs modules for credential-holding services use.
        StateDirectoryMode = "0700";
        # Creates (and tears down) the directory the socket lives in. The
        # socket itself is placed there by HERDR_SOCKET_PATH below; this
        # option alone does not move it.
        RuntimeDirectory = runtimeDirName;
        RuntimeDirectoryMode = "0750";
        Restart = "always";
        RestartSec = "5s";
      }
      // lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = "-${cfg.environmentFile}";
      };

      environment = {
        HOME = cfg.stateDir;
        # The actual pin. Without this herdr derives the socket from its config
        # directory and lands at ${cfg.stateDir}/.config/herdr/herdr.sock.
        HERDR_SOCKET_PATH = socketPath;
        # Not the socket mechanism — set so agent CLIs started in a pane get a
        # writable runtime dir rather than inheriting none.
        XDG_RUNTIME_DIR = runtimeDir;
      };
    };
  };
}
