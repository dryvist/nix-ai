# Shared launcher and profile renderer for AI CLIs using the macOS Seatbelt boundary.
# The defaults are OpenCode's; another CLI overrides the paths it owns.
#
# The profile and the env allowlist are the whole boundary. Every allowance is
# argued in opencode.sb; scripts/launch.sh only assembles the -D parameters.
{ pkgs, lib }:
{
  package,
  home,
  workRoot,
  localPorts ? [ ],
  extraEnv ? { },
  inheritedEnv ? [ ],
  binaryName ? "opencode",
  readRules ? [
    {
      kind = "subpath";
      path = ".config/opencode";
    }
  ],
  statePaths ? [
    ".local/share/opencode"
    ".local/state/opencode"
    ".cache/opencode"
  ],
  projectConfigFileRegex ? "opencode\\.json",
  projectConfigDirRegex ? "\\.opencode",
  appWriteExceptionRule ? "(allow file-write*\n  (regex #\"/\\.opencode/\\.gitignore$\"))",
}:
let
  # Build-time placeholders in the profile. Per-run paths arrive as -D parameters.
  localAllowRules = lib.concatMapStrings (
    port: "(allow network-outbound (remote ip \"localhost:${toString port}\"))\n"
  ) localPorts;
  appReadRules = lib.concatMapStrings (rule: "  (${rule.kind} \"${home}/${rule.path}\")\n") readRules;
  appStateRules = lib.concatMapStringsSep "\n" (path: "  (subpath \"${home}/${path}\")") statePaths;
  profile = pkgs.writeText "${binaryName}.sb" (
    builtins.replaceStrings
      [
        "@BINARY_NAME@"
        "@APP_READ_RULES@"
        "@APP_STATE_RULES@"
        "@PROJECT_CONFIG_FILE_REGEX@"
        "@PROJECT_CONFIG_DIR_REGEX@"
        "@APP_WRITE_EXCEPTION_RULE@"
        "@HOME@"
        "@LOCAL_PORTS@"
      ]
      [
        binaryName
        appReadRules
        appStateRules
        projectConfigFileRegex
        projectConfigDirRegex
        appWriteExceptionRule
        home
        localAllowRules
      ]
      (builtins.readFile ./opencode.sb)
  );

  extraEnvLines = lib.concatMapStrings (
    name: "envargs+=(${lib.escapeShellArg "${name}=${extraEnv.${name}}"})\n"
  ) (lib.attrNames extraEnv);
  # Caller-shell variables the tool needs, forwarded only when set.
  inheritedEnvLines = lib.optionalString (inheritedEnv != [ ]) ''
    for name in ${lib.concatStringsSep " " inheritedEnv}; do
      if [ -n "''${!name+x}" ]; then
        envargs+=("$name=''${!name}")
      fi
    done
  '';

  launcher = pkgs.writeShellApplication {
    name = binaryName;
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
    ];
    text =
      builtins.replaceStrings
        [
          "@BINARY_NAME@"
          "@HOME@"
          "@WORK_ROOT@"
          "@EXTRA_ENV@"
          "@INHERITED_ENV@"
          "@PROFILE@"
          "@REAL_BINARY@"
        ]
        [
          binaryName
          (lib.escapeShellArg home)
          (lib.escapeShellArg workRoot)
          extraEnvLines
          inheritedEnvLines
          "${profile}"
          "${package}/bin/${binaryName}"
        ]
        (builtins.readFile ./scripts/launch.sh);
  };
in
# Keep the package identity of the real binary: the CLI ownership checks match on pname and version.
launcher.overrideAttrs (old: {
  inherit (package) pname version;
  passthru = (old.passthru or { }) // {
    sandboxProfile = profile;
  };
})
