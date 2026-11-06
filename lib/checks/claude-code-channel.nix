# Claude Code release channel: latest, no soak, by owner decision.
#
# The cask stays claude-code@latest (lib/homebrew.nix), and Claude Code
# upgrades it itself (CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE in
# modules/claude/settings-env.nix). Changing either fails this check.
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.claude;
in
{
  claude-code-channel = helpers.mkDefaultsRegression {
    label = "Claude Code channel";
    checkName = "check-claude-code-channel";
    checks = [
      {
        name = "homebrew.casks.claudeCode";
        actual = map (cask: cask.name) (import ../homebrew.nix).casks.claudeCode;
        expected = [ "claude-code@latest" ];
      }
      {
        name = "settings.env.CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE";
        actual = cfg.settings.env.CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE or null;
        expected = "1";
      }
    ];
  };
}
