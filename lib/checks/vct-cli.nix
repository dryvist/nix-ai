{
  pkgs,
  hmConfig,
  hmConfigVctCli,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };

  packagePrograms =
    cfg: map (pkg: pkg.meta.mainProgram or pkg.pname or pkg.name or "") cfg.config.home.packages;
  defaultPrograms = packagePrograms hmConfig;
  enabledPrograms = packagePrograms hmConfigVctCli;
  getPkg =
    mainProgram:
    let
      matches = builtins.filter (
        pkg: (pkg.meta.mainProgram or pkg.pname or pkg.name or "") == mainProgram
      ) hmConfigVctCli.config.home.packages;
    in
    if matches == [ ] then
      throw "vct-cli: missing ${mainProgram} derivation in enabled home.packages"
    else
      builtins.head matches;
  criblPkg = getPkg "cribl";
  splunkPkg = getPkg "splunk";
in
{
  vct-cli-default-disabled =
    assert
      !(builtins.elem "cribl" defaultPrograms)
      || throw "vct-cli: cribl must stay out of home.packages when programs.vctCli.enable = false";
    assert
      !(builtins.elem "splunk" defaultPrograms)
      || throw "vct-cli: splunk must stay out of home.packages when programs.vctCli.enable = false";
    helpers.mkMarker "check-vct-cli-default-disabled" "vct-cli: default evaluation keeps both CLIs disabled";

  vct-cli-enabled-packages =
    assert
      builtins.elem "cribl" enabledPrograms
      || throw "vct-cli: enabling the module must add cribl to home.packages";
    assert
      builtins.elem "splunk" enabledPrograms
      || throw "vct-cli: enabling the module must add splunk to home.packages";
    helpers.mkMarker "check-vct-cli-enabled-packages" "vct-cli: enabling the module installs both CLIs";

  vct-cli-entrypoints = pkgs.runCommand "check-vct-cli-entrypoints" { } ''
    if ! ${pkgs.lib.getExe criblPkg} --help >/dev/null; then
      echo "FAIL: cribl --help did not run"
      exit 1
    fi

    if ! ${pkgs.lib.getExe splunkPkg} --help >/dev/null; then
      echo "FAIL: splunk --help did not run"
      exit 1
    fi

    touch $out
  '';
}
