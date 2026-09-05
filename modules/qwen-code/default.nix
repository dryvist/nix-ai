#
# Qwen Code Module — Aggregator
#
# Qwen Code (https://github.com/QwenLM/qwen-code) is Alibaba's terminal
# coding agent. Claude-Code-style UX for Qwen3-Coder and any other
# OpenAI/Anthropic/Gemini-compatible endpoint.
#
# Routes through the local MLX stack (llama-swap at
# http://127.0.0.1:11434/v1) by default — picks up the Qwen3-Coder
# model that backs the `coding` / `quickest` capability classes. Cloud
# Dashscope / OpenRouter / OpenAI access is opt-in via the `d-qwen`
# Doppler-wrapped shell alias.
#
# Why llm-agents.nix (not nixpkgs / brew / uvx): it tracks upstream closely,
# while nixpkgs 26.05 is frozen several minor versions back. Both package
# qwen-code for every supported system; a Homebrew formula did not, which is
# one of the reasons this stack could not leave the Mac. `installVia` still
# selects "nixpkgs" or "brew" for a host that wants either.
#
{
  config,
  lib,
  pkgs,
  llm-agents,
  ...
}:

let
  cfg = config.programs.qwen-code;
  llmAgents = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [
    ./options.nix
    ./settings.nix
  ];

  config = lib.mkIf cfg.enable {
    programs.qwen-code.package = lib.mkMerge [
      (lib.mkIf (cfg.installVia == "llm-agents") (lib.mkDefault llmAgents.qwen-code))
      (lib.mkIf (cfg.installVia == "nixpkgs") (lib.mkDefault pkgs.qwen-code))
    ];

    home = {
      packages = lib.optional (cfg.package != null) cfg.package;
      file.".qwen/.keep".text = "# Managed by Nix — programs.qwen-code\n";
    };
  };
}
