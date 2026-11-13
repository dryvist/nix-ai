# orca-server NixOS module check (x86_64-linux): the module evaluated on its
# own yields a unit that runs the packaged `orca serve` with telemetry
# disabled, binds every interface on the default port, opens that port, and
# runs as the dedicated orca user.
{
  pkgs,
  src,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  evaluated = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = "x86_64-linux";
    modules = [
      (src + "/modules/orca/nixos.nix")
      { services.orca-server.enable = true; }
    ];
  };
  cfg = evaluated.config;
  unit = cfg.systemd.services.orca-server;
  expectedExecStart = "${cfg.services.orca-server.package}/bin/orca serve --supervise --no-pairing --bind 0.0.0.0 --port 6768";
in
{
  orca-server-nixos-module =
    assert
      unit.serviceConfig.ExecStart == expectedExecStart
      || throw "orca-server ExecStart drifted: ${unit.serviceConfig.ExecStart}";
    assert
      unit.environment.ORCA_TELEMETRY_DISABLED == "1"
      || throw "orca-server must set ORCA_TELEMETRY_DISABLED=1";
    assert
      builtins.elem 6768 cfg.networking.firewall.allowedTCPPorts
      || throw "orca-server port 6768 is not opened in the firewall";
    assert
      unit.serviceConfig.User == "orca" && cfg.users.users.orca.isSystemUser
      || throw "orca-server must run as the dedicated orca system user";
    helpers.mkMarker "check-orca-server-nixos-module" "orca-server unit: ExecStart, telemetry env, firewall port, dedicated user";

  # Builds the package and runs the launcher on its bundled runtime.
  orca-server-package = pkgs.runCommand "check-orca-server-package" { } ''
    HOME=$TMPDIR ${cfg.services.orca-server.package}/bin/orca --help > /dev/null
    touch $out
  '';
}
