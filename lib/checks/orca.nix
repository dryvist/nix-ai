# Orca module checks (aarch64-darwin): enabled installs the package, whose
# bin/orca resolves to the bundled CLI, and defines no LaunchAgent; the default
# installs nothing.
{
  pkgs,
  hmConfig,
  hmConfigOrca,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  orcaPackages =
    config: builtins.filter (package: pkgs.lib.getName package == "orca") config.home.packages;
  hasOrca = config: orcaPackages config != [ ];
in
{
  orca-module =
    let
      cfg = hmConfigOrca.config;
    in
    assert
      hasOrca cfg || throw "Orca package missing from home.packages when programs.orca.enable = true";
    # deepSeq forces every agent definition, not only the one name asserted below.
    assert
      builtins.deepSeq cfg.launchd.agents (!(cfg.launchd.agents ? orca-telemetry))
      || throw "Orca must not define a telemetry LaunchAgent";
    helpers.mkMarker "check-orca-module" "Orca enabled: package installed, no LaunchAgent defined";

  orca-cli-link =
    let
      package = builtins.head (orcaPackages hmConfigOrca.config);
    in
    pkgs.runCommand "check-orca-cli-link" { } ''
      cli=${package}/bin/orca
      test -L "$cli" || { echo "bin/orca is not a symlink"; exit 1; }
      test -x "$cli" || { echo "bin/orca does not resolve to an executable"; exit 1; }
      case "$(readlink -f "$cli")" in
        */Orca.app/Contents/Resources/bin/orca) ;;
        *) echo "bin/orca resolves outside the bundled CLI: $(readlink -f "$cli")"; exit 1 ;;
      esac
      touch "$out"
    '';

  orca-module-negative =
    let
      cfg = hmConfig.config;
    in
    assert !(hasOrca cfg) || throw "Orca package must NOT be installed by default";
    assert
      !(cfg.launchd.agents ? orca-telemetry) || throw "Orca telemetry LaunchAgent must NOT be defined";
    helpers.mkMarker "check-orca-module-negative" "Orca default: package and LaunchAgent correctly absent";
}
