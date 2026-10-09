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

  codexQuota = pkgs.writeShellApplication {
    name = "codex-quota";
    runtimeInputs = [
      pkgs.jq
      pkgs.findutils
      pkgs.gnugrep
    ];
    text = builtins.readFile ./codex-quota.sh;
  };

  gate = pkgs.writeShellApplication {
    name = "agent-spawn-gate";
    # gnugrep: the prompt patterns use `\b` word boundaries.
    runtimeInputs = [
      pkgs.jq
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      codexQuota
    ];
    text = builtins.readFile ./agent-spawn-gate.sh;
  };

  # One Claude PreToolUse slot carries every policy: each script exits early
  # for tools it does not own, and the first deny wins.
  claudePreToolUse = lib.concatStringsSep "\n" (
    [ ''input="$(cat)"'' ]
    ++ lib.optional cfg.agentSpawnGate.enable ''
      decision="$(printf '%s' "$input" | ${gate}/bin/agent-spawn-gate)"
      if [ -n "$decision" ]; then printf '%s\n' "$decision"; exit 0; fi''
    ++ lib.optional cfg.worktreeAddGuard.enable ''printf '%s' "$input" | ${guard}/bin/worktree-add-guard "$@"''
  );
in
{
  options.programs.agentHooks.worktreeAddGuard.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Deny `git worktree add` (Claude Code and Codex both run this through a
      PreToolUse hook) whenever the destination is not under
      `<repo>/.worktrees/` or `<repo>/.claude/worktrees/`. On by default: it
      only tightens where a worktree may land, never blocks a normal git
      command.
    '';
  };

  options.programs.agentHooks.agentSpawnGate.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Deny Claude Code subagent spawns that break the delegation policy:
      models other than Haiku or Opus, effort below high, Opus on read-only
      scouting, and Claude implementation while `codex-quota` reports Codex
      quota. Also installs `codex-quota` on PATH.
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.agentSpawnGate.enable { home.packages = [ codexQuota ]; })

    # `programs.claude.hooks.preToolUse` only materializes a script file when
    # its value satisfies `builtins.isPath` (see nix-claude-code's
    # modules/hooks.nix); a package output interpolated to a string does not,
    # so the slot takes inline `lines` text instead — a wrapper that pipes the
    # tool call through each built policy. Shares this slot with
    # nix-claude-code's own `blockKeychainSecretReads`/
    # `blockExternalSubagentsInPrivateWorkspace` toggles: enabling either of
    # those alongside this fails the build (two writers to one option) rather
    # than silently dropping a guard — neither is set in this repo today.
    (lib.mkIf
      (config.programs.claude.enable && (cfg.worktreeAddGuard.enable || cfg.agentSpawnGate.enable))
      {
        programs.claude.hooks.preToolUse = lib.mkDefault claudePreToolUse;
      }
    )

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
