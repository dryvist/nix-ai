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
# Why nixpkgs (not brew / uvx): nixpkgs packages qwen-code as of 26.05.
# It used to come from a Homebrew formula, which had no Linux path and so was
# one of the reasons this stack could not leave the Mac. `installVia = "brew"`
# is still selectable for a host that wants the bottled build.
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.qwen-code;
in
{
  imports = [
    ./options.nix
    ./settings.nix
  ];

  config = lib.mkIf cfg.enable {
    programs.qwen-code.package = lib.mkIf (cfg.installVia == "nixpkgs") (
      lib.mkDefault pkgs.qwen-code
    );

    home.packages = lib.optional (cfg.package != null) cfg.package;

    home.file.".qwen/.keep".text = "# Managed by Nix — programs.qwen-code\n";
  };
}
