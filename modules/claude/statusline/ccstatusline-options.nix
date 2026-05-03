# ccstatusline Options
#
# sirmalloc/ccstatusline: feature-rich, actively maintained status line.
# Repository: https://github.com/sirmalloc/ccstatusline
#
{ lib, ... }:

{
  options.programs.claudeStatuslineCcstatusline = {
    enable = lib.mkEnableOption "Claude Code statusline (ccstatusline by sirmalloc)";
  };
}
