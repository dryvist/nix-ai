# ccstatusline Implementation
#
# Feature-rich Claude Code status line with native xhigh effort support.
# Uses bunx at runtime — no build-time hashes to maintain.
#
# Repository: https://github.com/sirmalloc/ccstatusline
# Configuration: ./ccstatusline.json
#
# Segments: model | cwd | worktree | branch | tokens | effort | 5h% | 7d%
# Effort levels: low / medium / high / xhigh / max (all rendered natively)
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claudeStatuslineCcstatusline;
  powerlineCfg = config.programs.claudeStatusline;
  daniel3303Cfg = config.programs.claudeStatuslineDaniel3303;

  configFile = ./ccstatusline.json;

in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !powerlineCfg.enable && !daniel3303Cfg.enable;
        message = ''
          Cannot enable more than one statusline implementation simultaneously.
          Disable programs.claudeStatusline (powerline) and programs.claudeStatuslineDaniel3303 (daniel3303)
          before enabling programs.claudeStatuslineCcstatusline.
        '';
      }
    ];

    programs.claude.statusLine = {
      enable = true;
      script = ''
        #!/usr/bin/env bash
        # ccstatusline by sirmalloc (semver-pinned for stability)
        export PATH="${pkgs.git}/bin:$PATH"
        exec ${pkgs.bun}/bin/bunx ccstatusline@'^2' --config ${configFile} "$@"
      '';
    };
  };
}
