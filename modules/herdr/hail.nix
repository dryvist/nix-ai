# herdr-hail — the Slack/Discord bridge, as a companion unit on the herdr guest.
#
# Imported by modules/herdr/nixos.nix; not exported as a module of its own,
# because it is meaningless without a herdr server on the same host.
#
# WHY A UNIT AND NOT A PLUGIN REGISTRATION. Upstream ships hail as a herdr
# plugin, but that route runs nothing unattended: the manifest declares one
# `[[panes]]` entrypoint and no `[[startup]]` hook, so a registered plugin sits
# idle until somebody opens `herdr plugin pane open hail/bridge`. The bridge
# reads exactly two variables — HERDR_SOCKET_PATH (src/herdr.ts) and
# HERDR_PLUGIN_CONFIG_DIR (src/config.ts) — both of which a unit can set.
#
# An earlier design read "plugin" as "separate service", gave it its own guest
# and forwarded the socket over SSH. Avoid that: hail's advantage over
# herdr-remote is "no tunnel, no relay", true only when it runs local.
{
  config,
  lib,
  pkgs,
  herdr-hail-src,
  ...
}:

let
  cfg = config.services.herdr;
  inherit (cfg) hail;

  # Read-only and world-readable on purpose: hail never writes to disk (nothing
  # in the upstream tree calls writeFile), and every secret arrives through
  # environmentFile, so nothing rendered here is sensitive.
  configDir = "/etc/herdr-hail";

  # Upstream's own DEFAULTS (src/config.ts), restated so `settings` can
  # override one field without naming the rest, and so the assertions below
  # read the EFFECTIVE value rather than only what the operator typed.
  settings = lib.recursiveUpdate {
    notifyOn = [
      "blocked"
      "done"
    ];
    pollIntervalMs = 1500;
    contextSource = "visible";
    contextLines = 12;
    slack = {
      enabled = false;
      allowedUsers = [ ];
    };
    discord = {
      enabled = false;
      allowedUsers = [ ];
      messageContent = false;
    };
  } hail.settings;
in
{
  options.services.herdr.hail = {
    enable = lib.mkEnableOption "the herdr-hail Slack/Discord bridge alongside the server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../herdr-hail/package.nix { src = herdr-hail-src; };
      defaultText = lib.literalExpression "pkgs.callPackage ../herdr-hail/package.nix { src = herdr-hail-src; }";
      description = "herdr-hail package to run.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = lib.literalExpression ''
        {
          slack = {
            enabled = true;
            channel = "C0123456789";
            allowedUsers = [ "U0123456789" ];
          };
        }
      '';
      description = ''
        Non-secret half of hail's config.json, rendered into /etc/herdr-hail
        and merged over upstream's defaults, so only differing fields need
        naming. Tokens do NOT belong here — this lands in the world-readable
        Nix store. Use `environmentFile`.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/var/lib/herdr/hail.env";
      description = ''
        systemd EnvironmentFile holding hail's tokens. Upstream fixes the
        names, and they win over config.json: SLACK_BOT_TOKEN, SLACK_APP_TOKEN,
        SLACK_CHANNEL, SLACK_ALLOWED_USERS, DISCORD_BOT_TOKEN,
        DISCORD_CHANNEL_ID, DISCORD_ALLOWED_USERS.

        There is no env override for the per-channel `enabled` flag, so an env
        file alone cannot switch a channel on — see the assertion below.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && hail.enable) {
    assertions = [
      {
        # hail computes `enabled = enabled && hasTokens` and exposes no env
        # override for the flag itself. A guest with perfect tokens and no
        # `enabled` here starts, connects, polls, and notifies nobody — a
        # healthy unit over a silent fleet, which reads exactly like a quiet
        # one. Fail at evaluation instead of at 3am.
        assertion = (settings.slack.enabled or false) || (settings.discord.enabled or false);
        message = ''
          services.herdr.hail is enabled but neither settings.slack.enabled nor
          settings.discord.enabled is true. herdr-hail has no environment
          override for those flags, so the bridge would run and deliver nothing.
        '';
      }
      {
        assertion = hail.environmentFile != null;
        message = ''
          services.herdr.hail needs an environmentFile: its tokens must not go
          in `settings`, which is rendered into the world-readable Nix store.
        '';
      }
    ];

    environment.etc."herdr-hail/config.json".source = pkgs.writeText "herdr-hail-config.json" (
      builtins.toJSON settings
    );

    systemd.services.herdr-hail = {
      description = "herdr-hail Slack/Discord bridge";
      wantedBy = [ "multi-user.target" ];
      # BindsTo, not merely After: the bridge's only job is watching panes over
      # herdr's socket, so it is meaningless without the server and should stop
      # with it rather than restart-loop against a socket that is not there.
      bindsTo = [ "herdr.service" ];
      after = [ "herdr.service" ];

      unitConfig = {
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      }
      // lib.optionalAttrs (cfg.onFailureUnit != null) { OnFailure = cfg.onFailureUnit; };

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe hail.package;
        # Same user as the server: the runtime directory is 0750 and owned by
        # it, and hail is a client of that socket, not a separate trust domain.
        User = cfg.user;
        Group = cfg.user;
        WorkingDirectory = cfg.stateDir;
        Restart = "always";
        RestartSec = "5s";
        EnvironmentFile = "-${hail.environmentFile}";
      };

      environment = {
        HOME = cfg.stateDir;
        HERDR_SOCKET_PATH = cfg.socketPath;
        HERDR_PLUGIN_CONFIG_DIR = configDir;
      };
    };
  };
}
