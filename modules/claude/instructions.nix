# Global Claude Code instructions and per-model effort.
#
# ~/.claude/CLAUDE.md imports the shared ~/.agents/AGENTS.md (built in
# ../default.nix from lib/shared-agent-instructions.nix) and appends the
# Claude-only section from ai-assistant-instructions, so Claude loads the same
# core instructions as Codex.
#
# modelSettings pins per-model effort so a runtime /effort pick cannot leave a
# model below the `effortLevel` floor in ../claude-config.nix: Opus and Fable
# run at high, Haiku (the subagent default) at xhigh.
{
  config,
  lib,
  ai-assistant-instructions,
  ...
}:
{
  config = lib.mkIf config.programs.claude.enable {
    home.file.".claude/CLAUDE.md" = {
      text =
        "@~/.agents/AGENTS.md\n\n"
        + builtins.readFile "${ai-assistant-instructions}/agentsmd/claude-code.md";
      # Replaces the hand-written file that predates this module.
      force = true;
    };

    programs.claude.settings.modelSettings = {
      claude-opus-5.effortLevel = "high";
      claude-opus-5-5.effortLevel = "high";
      claude-fable-5.effortLevel = "high";
      claude-fable-5-1.effortLevel = "high";
      claude-haiku-5-5.effortLevel = "xhigh";
    };
  };
}
