# OpenCode launcher: runs the real binary under the deny-default Seatbelt profile
# (opencode.sb) with an allowlisted environment.
#
# The profile and the env allowlist are the whole boundary. Every allowance is
# argued in opencode.sb; scripts/launch.sh only assembles the -D parameters.
{ pkgs, lib }:
{
  opencode,
  home,
  extraEnv ? { },
}:
let
  # @HOME@ is the only build-time placeholder in the profile. Per-run paths arrive as -D parameters.
  profile = pkgs.writeText "opencode.sb" (
    builtins.replaceStrings [ "@HOME@" ] [ home ] (builtins.readFile ./opencode.sb)
  );

  extraEnvLines = lib.concatMapStrings (
    name: "envargs+=(${lib.escapeShellArg "${name}=${extraEnv.${name}}"})\n"
  ) (lib.attrNames extraEnv);
in
let
  launcher = pkgs.writeShellApplication {
    name = "opencode";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
    ];
    text =
      builtins.replaceStrings
        [ "@HOME@" "@EXTRA_ENV@" "@PROFILE@" "@OPENCODE@" ]
        [
          (lib.escapeShellArg home)
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
