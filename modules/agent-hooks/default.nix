# Cross-harness agent policy hooks.
#
# One script, wired to both Claude Code and Codex, so a policy that must hold
# regardless of which CLI is driving doesn't need a second implementation.
{
  config,
  lib,
  pkgs,
  marketplaceInputs,
  ...
}:

let
  cfg = config.programs.agentHooks;

  inherit (import ../claude/plugins { inherit lib marketplaceInputs; }) enabledPlugins;

  # Plan mode may only present a plan after the agentops plan skill ran this
  # session: the transcript holds its Skill call or its slash command. Both
  # patterns need unescaped quotes, so text that merely mentions them does not match.
  planSkillGate = ''f="$(${pkgs.jq}/bin/jq -r .transcript_path)"; ${pkgs.gnugrep}/bin/grep -qE '"skill":"agentops:plan"|"content":"<command-name>/agentops:plan<' "$f" || { echo 'Run the agentops:plan skill before presenting the plan.' >&2; exit 2; }'';

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

  codexQuota = pkgs.writeShellApplication {
    name = "codex-quota";
    runtimeInputs = [
      config.programs.codex.package
      pkgs.jq
      pkgs.findutils
      pkgs.gnugrep
    ];
    text = builtins.readFile ./codex-quota.sh;
  };

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

  options.programs.agentHooks.planSkillGate.enable = lib.mkOption {
    type = lib.types.bool;
    default = enabledPlugins."agentops@agentops-marketplace" or false;
    defaultText = lib.literalMD "whether the `agentops@agentops-marketplace` plugin is enabled";
    description = ''
      Block Claude Code's `ExitPlanMode` until the session has run the
      agentops `plan` skill, so every plan starts from it.
    '';
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

    (lib.mkIf (config.programs.claude.enable && cfg.planSkillGate.enable) {
      programs.claude.hooks.events.PreToolUse = [
        {
          matcher = "ExitPlanMode";
          hooks = [
            {
              type = "command";
              command = planSkillGate;
              timeout = 10;
            }
          ];
        }
      ];
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
  ];
}
