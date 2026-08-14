# programs.vctCli regression tests.
{
  pkgs,
  hmConfig,
  hmConfigVctCli,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };

  # What enabling the module adds on top of the default (disabled) evaluation.
  # Empty when the module leaks into the default config, so one assertion pins
  # both halves of the toggle.
  added = lib.subtractLists hmConfig.config.home.packages hmConfigVctCli.config.home.packages;
  programs = builtins.sort (a: b: a < b) (map (pkg: pkg.meta.mainProgram) added);
in
{
  vct-cli-toggle =
    assert lib.assertMsg
      (
        programs == [
          "cribl"
          "splunk"
        ]
      )
      "programs.vctCli.enable must add exactly the cribl and splunk CLIs, got ${builtins.toJSON programs}";
    helpers.mkMarker "check-vct-cli-toggle" "vct-cli: disabled by default, enable adds cribl + splunk";

  # Proves the generated console scripts run — the build alone only proves the
  # wheel imports.
  vct-cli-entrypoints = pkgs.runCommand "check-vct-cli-entrypoints" { } (
    lib.concatMapStrings (pkg: "${lib.getExe pkg} --help >/dev/null || exit 1\n") added + "touch $out"
  );
}
