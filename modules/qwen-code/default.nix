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
# Why brew (not nixpkgs / uvx):
#   - Not packaged in nixpkgs.
#   - Homebrew has a bottled formula (`qwen-code`) — this is the
#     install-order rule's preferred path after nixpkgs and a local
#     buildNpmPackage derivation. The npm-derivation path is deferred
#     (qwen-code's workspace + cross-platform optionalDependencies
#     need deeper packaging work; see modules/qwen-code/packages.nix).
#
# The brew install itself lives in nix-darwin (homebrew.brews is a
# nix-darwin option, not a home-manager one). This module exposes the
# required formula list via the lib.brewFormulae flake output for
# nix-darwin to consume; the module itself handles config, an
# eval-time assertion that gates installVia="brew" to darwin, and a
# soft activation-time warning when the binary is missing.
#
{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.qwen-code;
in
{
  imports = [
    ./options.nix
    ./settings.nix
    ./packages.nix
  ];

  config = lib.mkIf cfg.enable {
    home.file.".qwen/.keep".text = "# Managed by Nix — programs.qwen-code\n";
  };
}
