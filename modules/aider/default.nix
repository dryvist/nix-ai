#
# Aider Module — Aggregator
#
# AI pair programming in the terminal, configured to route through the local
# MLX stack (llama-swap at http://127.0.0.1:11434/v1) by default so it works
# with open-source models (Qwen3-Coder, Gemma, etc.) without cloud API keys.
#
# Cloud access is opt-in via the `d-aider` shell alias (Doppler-injected) or
# by switching programs.aider.routing to "bifrost".
#
# Upstream: https://github.com/paul-gauthier/aider
#
{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.aider;
in
{
  imports = [
    ./options.nix
    ./settings.nix
    ./packages.nix
  ];

  config = lib.mkIf cfg.enable {
    home.file.".aider/.keep".text = "# Managed by Nix — programs.aider\n";
  };
}
