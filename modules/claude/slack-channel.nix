# Slack channel opt-in for interactive Claude Code sessions.
#
# Owns the programs.claude.slackChannel option and the zsh hook that sources
# ./slack-channel.zsh. The marketplace and plugin wiring stays in
# modules/claude-config.nix, which reads this option.
{ config, lib, ... }:
{
  options.programs.claude.slackChannel.enable =
    lib.mkEnableOption "the Slack channel plugin (claude-channel-slack) for interactive Claude Code sessions";

  config.programs.zsh.initContent = lib.mkIf config.programs.claude.slackChannel.enable (
    lib.mkAfter "source ${./slack-channel.zsh}"
  );
}
