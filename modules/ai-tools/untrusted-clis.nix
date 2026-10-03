# Untrusted agent CLIs installed by the ai-tools set.
#
# Added to home.packages only when programs.ai.untrustedClis.enable is true
# (modules/default.nix). opencode, cursor-agent, qwen-code and cecli are
# gated by their own programs.<name>.enable; claude-zai by modules/ai-shell.nix;
# omo-senpi additionally by programs.ai.ohMyOpenagent.enable.
{
  pkgs,
  llm-agents,
  ohMyOpenagent ? false,
}:
let
  versions = import ../../lib/versions.nix;
in
[
  # GitHub Copilot CLI (`copilot`). Not in nixpkgs; llm-agents.nix packages it
  # for both supported systems. Config (~/.copilot) comes from modules/copilot.nix.
  llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.copilot-cli

  # `gh-copilot` — the older gh extension, kept for the shell-suggest workflow.
  # Source: https://github.com/github/gh-copilot
  (pkgs.writeShellScriptBin "gh-copilot" ''
    exec ${pkgs.bun}/bin/bunx --bun @githubnext/github-copilot-cli@${versions.ghCopilot} "$@"
  '')

  # Claude Flow — multi-agent orchestration.
  # Source: https://github.com/ruvnet/claude-flow  NPM: claude-flow (pinned)
  (pkgs.writeShellScriptBin "claude-flow" ''
    exec ${pkgs.bun}/bin/bunx --bun claude-flow@${versions.claudeFlow} "$@"
  '')

]
# Oh My OpenAgent, Senpi edition — standalone senpi engine with the OMO
# extension built in (beta channel). Opt-in: only with
# programs.ai.ohMyOpenagent.enable, on top of the untrusted CLI gate.
# Source: https://github.com/code-yeongyu/oh-my-openagent
# NPM: omo-ai (pinned beta version; the `latest` tag is a placeholder, see
# lib/versions.nix). The Ultimate/Light plugin editions are not installed here.
#
# Named omo-senpi, not `omo`: the Codex Light installer links its own runtime
# wrapper at ~/.local/bin/omo (ahead of this dir on PATH), and bare `omo` on
# npm is an unrelated package by a different author.
++ pkgs.lib.optional ohMyOpenagent (
  pkgs.writeShellScriptBin "omo-senpi" ''
    exec ${pkgs.bun}/bin/bunx --bun omo-ai@${versions.omoSenpi} "$@"
  ''
)
