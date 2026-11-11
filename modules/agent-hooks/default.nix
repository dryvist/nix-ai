# Cross-harness agent policy hooks.
#
# One script, wired to both Claude Code and Codex, so a policy that must hold
# regardless of which CLI is driving doesn't need a second implementation.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.agentHooks;

  guard = pkgs.writeShellApplication {
    name = "worktree-add-guard";
    # gnused/gnugrep: the script's `sed -E 's/…/\n/g'` needs a GNU sed (BSD
    # sed inserts a literal `n`, not a newline) and its `\b` word boundaries
    # need GNU grep. Codex's own PATH when it invokes this hook is
    # unverified, so every tool the script calls must ship with it rather
    # than be assumed present.
    runtimeInputs = [
      pkgs.jq
      pkgs.git
      pkgs.gnused
      pkgs.gnugrep
    ];
    text = builtins.readFile ./worktree-add-guard.sh;
  };

  # The rollout selection lives once in codex-rollouts.sh and is inlined ahead
  # of each consumer's body, so codex-quota and the metrics reader share one copy.
  codexRollouts = builtins.readFile ./codex-rollouts.sh;

  codexQuota = pkgs.writeShellApplication {
    name = "codex-quota";
    runtimeInputs = [
      pkgs.jq
      pkgs.findutils
      pkgs.gnugrep
    ];
    text = codexRollouts + builtins.readFile ./codex-quota.sh;
  };

  codexQuotaMetrics = pkgs.writeShellApplication {
    name = "codex-quota-metrics";
    runtimeInputs = [
      pkgs.jq
      pkgs.findutils
      pkgs.gnugrep
    ];
    text = codexRollouts + builtins.readFile ./codex-quota-metrics.sh;
  };

  # Generic pusher: POSTs whatever its reader arguments print. Each reader prints
  # Prometheus exposition and exits non-zero when it has no reading.
  quotaPush = pkgs.writeShellApplication {
    name = "agent-quota-push";
    runtimeInputs = [
      pkgs.curl
      pkgs.gnugrep
    ];
    text = builtins.readFile ./quota-push.sh;
  };

  # The readers the pusher runs. Codex is the only one today.
  quotaReaders = [ codexQuotaMetrics ];

  quotaCfg = cfg.codexQuotaPush;

  # Runs start at minute 3 and step by the interval. launchd has no skew option,
  # so this offset keeps runs off :00, :15, :30 and :45; the assertions enforce it.
  quotaSlots = lib.genList (k: 3 + k * quotaCfg.intervalMinutes) 60;
  quotaMinutes = lib.filter (m: m < 60) quotaSlots;
  onQuarterHour = m: lib.mod m 15 == 0;

  # One Claude PreToolUse slot carries every policy: each script exits early
  # for tools it does not own, and the first deny wins.
  claudePreToolUse = lib.concatStringsSep "\n" (
    [ ''input="$(cat)"'' ]
    ++ lib.optional cfg.worktreeAddGuard.enable ''printf '%s' "$input" | ${guard}/bin/worktree-add-guard "$@"''
  );
in
{
  options.programs.agentHooks.worktreeAddGuard.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Deny raw `codex exec` from a tool shell, and deny `git worktree add`
      (Claude Code and Codex both run this through a PreToolUse hook) whenever
      the destination is not under `<repo>/.worktrees/` or
      `<repo>/.claude/worktrees/`. On by default: it only restricts these
      specific shell commands.
    '';
  };

  options.programs.agentHooks.codexQuotaPush = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Publish the Codex quota reading as Prometheus metrics. A launchd agent
        runs `agent-quota-push` with the Codex reader every `intervalMinutes`
        and POSTs the exposition to `url`, authenticated with the token in
        `tokenFile`. Enabling it requires both `url` and `tokenFile`. Darwin only.
      '';
    };
    url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Import endpoint the exposition is POSTed to: the metrics proxy's DNS name
        and path. No default. The host's private configuration sets it, and the
        agent receives it as AGENT_QUOTA_WRITE_URL.
      '';
    };
    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to a file holding the bearer token for `url`. curl reads the file at
        push time, so the token is never copied into the store, placed in an
        argument or written to the log. The host's private configuration sets the
        path, and the agent receives it as AGENT_QUOTA_WRITE_TOKEN_FILE.
      '';
    };
    intervalMinutes = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = ''
        Minutes between pushes. Runs start at minute 3 and step by this interval.
        An interval that would put a run on :00, :15, :30 or :45 fails an assertion.
      '';
    };
  };

  config = lib.mkMerge [
    # `codex-quota` is the one quota check; the ai-delegation plugin's router
    # and judge call it to decide whether Codex answers.
    { home.packages = [ codexQuota ]; }

    # `programs.claude.hooks.preToolUse` only materializes a script file when
    # its value satisfies `builtins.isPath` (see nix-claude-code's
    # modules/hooks.nix); a package output interpolated to a string does not,
    # so the slot takes inline `lines` text instead — a wrapper that pipes the
    # tool call through each built policy. Shares this slot with
    # nix-claude-code's own `blockKeychainSecretReads`/
    # `blockExternalSubagentsInPrivateWorkspace` toggles: enabling either of
    # those alongside this fails the build (two writers to one option) rather
    # than silently dropping a guard — neither is set in this repo today.
    (lib.mkIf (config.programs.claude.enable && cfg.worktreeAddGuard.enable) {
      programs.claude.hooks.preToolUse = lib.mkDefault claudePreToolUse;
    })

    (lib.mkIf (cfg.worktreeAddGuard.enable && config.programs.codex.enable) {
      programs.codex.hooks.events.PreToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "${guard}/bin/worktree-add-guard";
              timeout = 10;
            }
          ];
        }
      ];
    })

    (lib.mkIf quotaCfg.enable {
      assertions = [
        {
          assertion = quotaCfg.url != null;
          message = "programs.agentHooks.codexQuotaPush.url must be set when codexQuotaPush.enable is true.";
        }
        {
          assertion = quotaCfg.tokenFile != null;
          message = "programs.agentHooks.codexQuotaPush.tokenFile must be set when codexQuotaPush.enable is true.";
        }
        {
          assertion = quotaCfg.intervalMinutes >= 1 && !(lib.any onQuarterHour quotaMinutes);
          message = "programs.agentHooks.codexQuotaPush.intervalMinutes must be at least 1 and must not put a run on :00, :15, :30 or :45.";
        }
      ];
    })

    (lib.mkIf (quotaCfg.enable && pkgs.stdenv.hostPlatform.isDarwin) {
      launchd.agents.codex-quota-push = {
        enable = true;
        config = {
          Label = "dev.codex-quota-push";
          ProgramArguments = [ (lib.getExe quotaPush) ] ++ map lib.getExe quotaReaders;
          StartCalendarInterval = map (minute: { Minute = minute; }) quotaMinutes;
          RunAtLoad = false;
          EnvironmentVariables = {
            AGENT_QUOTA_WRITE_URL = quotaCfg.url;
            AGENT_QUOTA_WRITE_TOKEN_FILE = quotaCfg.tokenFile;
          };
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/codex-quota-push.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/codex-quota-push.log";
        };
      };
    })
  ];
}
