# Global Claude Code instructions and per-model effort.
#
# ~/.claude/CLAUDE.md imports the shared ~/.agents/AGENTS.md (built in
# ../default.nix from lib/shared-agent-instructions.nix) and appends the
# Claude-only section from the catalog instructions package, so Claude loads the same
# core instructions as Codex.
#
# modelSettings pins per-model effort so a runtime /effort pick cannot leave a
# model below the `effortLevel` floor in ../claude-config.nix: Opus and Fable
# run at high, Haiku (the subagent default) at xhigh.
{
  config,
  lib,
  pkgs,
  ai-llm-prompts,
  ...
}:
let
  instructions = import ../../lib/catalog-instructions.nix { inherit ai-llm-prompts pkgs; };
  claudeInstructions = pkgs.runCommand "claude-instructions" { } ''
    printf '@~/.agents/AGENTS.md\n\n' > "$out"
    cat "${instructions.pkg}/agentsmd/claude-code.md" >> "$out"
  '';
in
{
  config = lib.mkIf config.programs.claude.enable {
    home.file.".claude/CLAUDE.md" = {
      source = claudeInstructions;
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

    # Load each directory's AGENTS.md beside its CLAUDE.md files. By default
    # Claude Code skips AGENTS.md wherever a CLAUDE.md or CLAUDE.local.md exists.
    programs.claude.settings.pluginConfigs."cc-plugin-agents-md@builtin".options.instructionFiles =
      "claude-md-and-agents-md";
  };
}
