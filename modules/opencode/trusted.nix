{ pkgs, lib }:
{
  package,
  launchPrefix ? [ ],
  gatewayKeyLaunchPrefix ? null,
  gatewayKeyEnv ? null,
  extraEnv ? { },
}:
let
  envPrefix =
    lib.optionalString (extraEnv != { })
      "env ${lib.escapeShellArgs (lib.mapAttrsToList (name: value: "${name}=${value}") extraEnv)} ";
  launchPrefixArgs = lib.escapeShellArgs launchPrefix;
  gatewayPrefixArgs =
    if gatewayKeyLaunchPrefix == null then
      launchPrefixArgs
    else
      lib.escapeShellArgs (gatewayKeyLaunchPrefix ++ launchPrefix);
  executable = lib.escapeShellArg "${package}/bin/opencode";
  text =
    if gatewayKeyLaunchPrefix == null then
      ''
        exec ${envPrefix}${launchPrefixArgs} ${executable} "$@"
      ''
    else
      ''
        if [ -n "''${${gatewayKeyEnv}:-}" ]; then
          exec ${envPrefix}${launchPrefixArgs} ${executable} "$@"
        fi
        exec ${envPrefix}${gatewayPrefixArgs} ${executable} "$@"
      '';
  launcher = pkgs.writeShellApplication {
    name = "opencode";
    runtimeInputs = [ pkgs.coreutils ];
    inherit text;
  };
in
launcher.overrideAttrs (old: {
  pname = package.pname or package.name;
  version = package.version or "unknown";
  passthru = (old.passthru or { }) // {
    realPackage = package;
  };
})
