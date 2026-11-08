# Orca module checks (aarch64-darwin): enabled installs the package and the
# telemetry-off login agent; the default installs neither.
{
  pkgs,
  hmConfig,
  hmConfigOrca,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  hasOrca = config: builtins.any (package: pkgs.lib.getName package == "orca") config.home.packages;
in
{
  orca-launchd =
    let
      cfg = hmConfigOrca.config;
      agent = cfg.launchd.agents.orca-telemetry;
      args = agent.config.ProgramArguments;
      expectedArgs = [
        "/bin/launchctl"
        "setenv"
        "ORCA_TELEMETRY_DISABLED"
        "1"
      ];
    in
    assert
      hasOrca cfg || throw "Orca package missing from home.packages when programs.orca.enable = true";
    assert agent.enable || throw "Orca telemetry LaunchAgent must be enabled";
    assert
      args == expectedArgs
      || throw "Orca telemetry LaunchAgent ProgramArguments: ${builtins.concatStringsSep " " args}";
    assert
      (agent.config.RunAtLoad or false) || throw "Orca telemetry LaunchAgent must have RunAtLoad = true";
    helpers.mkMarker "check-orca-launchd" "Orca enabled: package installed, launchctl setenv ORCA_TELEMETRY_DISABLED 1 at load";

  orca-launchd-negative =
    let
      cfg = hmConfig.config;
    in
    assert !(hasOrca cfg) || throw "Orca package must NOT be installed by default";
    assert
      !(cfg.launchd.agents ? orca-telemetry)
      || throw "Orca telemetry LaunchAgent must NOT be defined by default";
    helpers.mkMarker "check-orca-launchd-negative" "Orca default: package and LaunchAgent correctly absent";
}
