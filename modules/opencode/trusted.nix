{ pkgs, lib }:
{
  package,
  launchPrefix ? [ ],
}:
let
  launcher = pkgs.writeShellApplication {
    name = "opencode";
    text = ''
      exec ${lib.escapeShellArgs launchPrefix} ${lib.escapeShellArg "${package}/bin/opencode"} "$@"
    '';
  };
in
launcher.overrideAttrs (old: {
  pname = package.pname or package.name;
  version = package.version or "unknown";
  passthru = (old.passthru or { }) // {
    realPackage = package;
  };
})
