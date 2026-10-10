# OpenCode launcher: runs the real binary under the deny-default Seatbelt profile
# (opencode.sb) with an allowlisted environment.
#
# The profile and the env allowlist are the whole boundary. Every allowance is
# argued in opencode.sb; scripts/launch.sh only assembles the -D parameters.
{ pkgs, lib }:
{
  opencode,
  home,
  workRoot,
  localPorts ? [ ],
  extraEnv ? { },
}:
let
  # Build-time placeholders in the profile. Per-run paths arrive as -D parameters.
  localAllowRules = lib.concatMapStrings (
    port: "(allow network-outbound (remote ip \"localhost:${toString port}\"))\n"
  ) localPorts;
  profile = pkgs.writeText "opencode.sb" (
    builtins.replaceStrings [ "@HOME@" "@LOCAL_PORTS@" ] [ home localAllowRules ] (
      builtins.readFile ./opencode.sb
    )
  );

  extraEnvLines = lib.concatMapStrings (
    name: "envargs+=(${lib.escapeShellArg "${name}=${extraEnv.${name}}"})\n"
  ) (lib.attrNames extraEnv);

  launcher = pkgs.writeShellApplication {
    name = "opencode";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
    ];
    text =
      builtins.replaceStrings
        [
          "@HOME@"
          "@WORK_ROOT@"
          "@EXTRA_ENV@"
          "@PROFILE@"
          "@OPENCODE@"
        ]
        [
          (lib.escapeShellArg home)
          (lib.escapeShellArg workRoot)
          extraEnvLines
          "${profile}"
          "${opencode}/bin/opencode"
        ]
        (builtins.readFile ./scripts/launch.sh);
  };
in
# Keep the package identity of the real binary: the CLI ownership checks match on pname and version.
launcher.overrideAttrs (_: {
  pname = "opencode";
  inherit (opencode) version;
})
