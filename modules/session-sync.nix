# Mac-to-Mac AI session sync.
#
# Pushes session history to a peer Mac on a timer so a conversation started on
# one machine can be resumed on the other, and so the corpus survives losing
# either machine. Push-only by design: the peer needs no access to this host.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.sessionSync;
  logDir = "${config.home.homeDirectory}/Library/Logs/session-sync";
in
{
  options.programs.sessionSync = {
    enable = lib.mkEnableOption "hourly push of AI session history to a peer Mac";

    remote = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "SSH destination of the peer, e.g. `host` or `user@host`. Required when enabled.";
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        ".claude"
        ".codex"
        ".gemini"
        ".antigravity"
        ".qwen"
        # OpenCode keeps sessions in its data dir (sqlite + storage/), not
        # under ~/.config/opencode, which is Nix-owned config only.
        ".local/share/opencode"
      ];
      description = ''
        Home-relative directories to push. Each is synced into the same path on
        the peer, so a session's project directory resolves identically on both.
      '';
    };

    excludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # Credentials. Every agent re-authenticates per machine, so these buy
        # nothing on the peer and copying them would put live secrets on a
        # second host purely as a side effect of a history sync.
        ".credentials.json"
        "auth.json"
        "oauth_creds.json"
        "antigravity-oauth-token"
        "mcp-oauth-locks"
        # Machine-local caches that Nix or the tools themselves repopulate.
        # `security` holds a Python venv whose binaries are built for this
        # machine, and `plugins` is a Nix-managed cache; both are large enough
        # to dominate an hourly transfer while being worthless on the peer.
        # `.tmp` is Codex's marketplace/plugin cache — 147 MB and 6,122 files
        # on this machine, more than every Codex session combined, and it
        # regenerates on demand.
        "plugins/"
        "security/"
        ".tmp/"
        ".DS_Store"
        # Per-machine rendered configuration. home-manager writes these as
        # regular files (an activation merge, not a store symlink), so
        # `--no-links` does not protect them: with `--update`, whichever host
        # rebuilt most recently overwrites the peer's copy, handing it this
        # host's OTEL host.name and other machine-specific settings.
        #
        # rsync runs once per top-level path (each of `paths` is its own
        # transfer root), and this list is shared across every one of those
        # runs, so a leading "/" anchors the pattern to the root of whichever
        # path is currently being synced rather than to `$HOME`. That is why
        # ".claude/settings.json" would be wrong here: `.claude` is already
        # the transfer root, so the pattern must start from what is inside it.
        "/settings.json" # ~/.claude/settings.json, ~/.qwen/settings.json
        "/settings.local.json" # ~/.claude/settings.local.json
        "/config.toml" # ~/.codex/config.toml
        "/antigravity-cli/settings.json" # ~/.gemini/antigravity-cli/settings.json
      ];
      description = "rsync exclude patterns, applied to every path.";
    };

    interval = lib.mkOption {
      type = lib.types.int;
      default = 3600;
      description = "Seconds between pushes. launchd runs a missed interval once the machine wakes.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.remote != "";
        message = "programs.sessionSync.remote must name the peer to push to.";
      }
    ];

    launchd.agents.session-sync = {
      enable = true;
      config = {
        Label = "dev.session-sync";
        ProgramArguments = [
          "${./scripts/session-sync.sh}"
          (lib.getExe pkgs.rsync)
          "/usr/bin/ssh"
          cfg.remote
          logDir
          "${config.home.homeDirectory}/Library/Caches/session-sync.lock"
          "--paths"
        ]
        ++ cfg.paths
        ++ [ "--excludes" ]
        ++ cfg.excludes;
        StartInterval = cfg.interval;
        RunAtLoad = false;
        ProcessType = "Background";
        LowPriorityIO = true;
        Nice = 10;
        EnvironmentVariables.HOME = config.home.homeDirectory;
        StandardOutPath = "${logDir}/agent.log";
        StandardErrorPath = "${logDir}/agent.error.log";
      };
    };
  };
}
