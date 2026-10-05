{ pkgs, hmConfigDarwin }:
let
  cfg = hmConfigDarwin.config;
  installed = builtins.any (package: pkgs.lib.getName package == "zcode-job") cfg.home.packages;
in
{
  zcode-job-darwin-package =
    assert installed;
    assert cfg.programs.zcode-job.disabled;
    assert !(builtins.hasAttr "zcode-job/config.json" cfg.xdg.configFile);
    pkgs.writeText "zcode-job-darwin-package" "package installed; connection config remains disabled";
}
