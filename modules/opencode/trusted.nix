{ pkgs, lib }:
{
  package,
  launchPrefix ? [ ],
  extraEnv ? { },
}:
let
  envPrefix =
    lib.optionalString (extraEnv != { })
      "env ${lib.escapeShellArgs (lib.mapAttrsToList (name: value: "${name}=${value}") extraEnv)} ";
  launchPrefixArgs = lib.escapeShellArgs launchPrefix;
  launcher = pkgs.writeShellApplication {
    name = "opencode";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      exec ${envPrefix}${launchPrefixArgs} ${lib.escapeShellArg "${package}/bin/opencode"} "$@"
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
