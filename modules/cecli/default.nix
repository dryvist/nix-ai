#
# cecli Module — Aggregator
#
# AI pair programming in the terminal. cecli is an actively maintained
# fork of Aider (https://github.com/cecli-dev/cecli, PyPI: cecli-dev) that
# preserves Aider's UX — including a backward-compat `aider-ce` entry
# point — while shipping bug fixes and new features.
#
# Routes through the local MLX stack (llama-swap at
# http://127.0.0.1:11434/v1) so it works with open-source models
# (Qwen3-Coder, Gemma, etc.) without cloud API keys. Cloud access is
# opt-in via the `d-cecli` shell alias (Doppler-injected).
#
# Why a local Nix derivation (not nixpkgs / brew):
#   - Not packaged in nixpkgs.
#   - Not packaged in Homebrew.
#   - Per the install-order rule, tier 2 (local buildPythonApplication)
#     applies. See modules/cecli/package.nix for the build definition,
#     transitive overrides, and version pin. Tests are skipped via
#     doCheck = false to avoid the macOS Nix sandbox SIGKILL on
#     sounddevice/soundfile/pydub test phases.
#
{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.cecli;
in
{
  imports = [
    ./options.nix
    ./settings.nix
    ./packages.nix
  ];

  config = lib.mkIf cfg.enable {
    home.file.".cecli/.keep".text = "# Managed by Nix — programs.cecli\n";
  };
}
