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
    runtimeInputs = [
      pkgs.jq
      pkgs.git
    ];
    text = builtins.readFile ./worktree-add-guard.sh;
  };
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

  config = lib.mkIf cfg.worktreeAddGuard.enable (
    lib.mkMerge [
      # `programs.claude.hooks.preToolUse` only materializes a script file
      # when its value satisfies `builtins.isPath` (see nix-claude-code's
      # modules/hooks.nix); a package output interpolated to a string does
      # not, so the slot takes inline `lines` text instead — a one-line
      # wrapper that execs the built guard. Shares this slot with
      # nix-claude-code's own `blockKeychainSecretReads`/
      # `blockExternalSubagentsInPrivateWorkspace` toggles: enabling either
      # of those alongside this fails the build (two writers to one
      # option) rather than silently dropping a guard — neither is set in
      # this repo today.
      (lib.mkIf config.programs.claude.enable {
        programs.claude.hooks.preToolUse = lib.mkDefault ''
          exec ${guard}/bin/worktree-add-guard "$@"
        '';
      })

      (lib.mkIf config.programs.codex.enable {
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
    ]
  );
}
