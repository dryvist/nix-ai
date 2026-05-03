# Claude Statusline Module
#
# Three available implementations (mutually exclusive — enable exactly one):
#
#   programs.claudeStatuslineCcstatusline.enable = true;  # Active (ccstatusline)
#   programs.claudeStatuslineDaniel3303.enable = true;    # Dormant (daniel3303 fork)
#   programs.claudeStatusline.enable = true;              # Dormant (claude-powerline)
#
# ccstatusline and powerline use bunx at runtime (no build-time hashes); daniel3303 runs a local bash script.
{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.claudeStatusline;
in
{
  imports = [
    ./options.nix
    ./powerline.nix
    ./daniel3303-options.nix
    ./daniel3303.nix
    ./ccstatusline-options.nix
    ./ccstatusline.nix
  ];

  config = lib.mkIf cfg.enable { };
}
