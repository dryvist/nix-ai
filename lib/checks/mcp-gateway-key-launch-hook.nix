# Exercise the generated Claude launcher with Bash and coreutils only.
{
  pkgs,
  mkHmConfig,
}:
let
  inherit (pkgs) lib;
  fakeClaude =
    pkgs.runCommand "fake-claude-test-target" { nativeBuildInputs = [ pkgs.coreutils ]; }
      ''
        mkdir -p "$out/bin"
        ln -s "${pkgs.bash}/bin/bash" "$out/bin/claude"
      '';
  printenvCommand = "exec ${pkgs.coreutils}/bin/printenv \"$@\"";
  hmConfigWithoutHook = mkHmConfig [ { programs.claude.package = fakeClaude; } ];
  hmConfigWithHook = mkHmConfig [
    {
      programs.aiMcp.gatewayKeyLaunchPrefixFor = { callerId, env }: [
        "${pkgs.coreutils}/bin/env"
        "--"
        "${env}=${callerId}-fixture-key"
      ];
      programs.claude.package = fakeClaude;
    }
  ];
  launcherPackage =
    hm:
    lib.findFirst (package: (package.name or "") == "agent-cli-launchers") null hm.config.home.packages;
  wrappersNull = (launcherPackage hmConfigWithoutHook).passthru.gatewayWrappers;
  wrappersWithHook = (launcherPackage hmConfigWithHook).passthru.gatewayWrappers;
  launcherCheck =
    assert
      hmConfigWithoutHook.config.programs.aiMcp.gatewayKeyLaunchPrefixFor == null
      || throw "The gateway-key launch-prefix hook must default to null";
    assert
      hmConfigWithHook.config.programs.aiMcp.gatewayKeyLaunchPrefixFor != null
      || throw "The gateway-key fixture did not set the launch-prefix hook";
    assert
      builtins.attrNames wrappersWithHook == [ "claude" ]
      || throw "The key hook wrapped an unexpected launcher: ${builtins.toJSON (builtins.attrNames wrappersWithHook)}";
    assert
      wrappersNull == { }
      || throw "The launch-prefix hook defaulted on and changed launchers without a host override";
    pkgs.runCommand "check-mcp-gateway-key-launch-hook" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
      set -euo pipefail
      wrapper=${lib.escapeShellArg (builtins.toString wrappersWithHook.claude)}
      key_env=GATEWAY_KEY_CLAUDE_CODE
      spaced_env_name='WRAPPER ARG WITH SPACE'

      missing_key_output=$("${pkgs.coreutils}/bin/env" -u "$key_env" -- \
        "$spaced_env_name=argv-sentinel" \
        "$wrapper" -c ${lib.escapeShellArg printenvCommand} claude "$key_env" "$spaced_env_name")
      expected_missing_key_output=$(printf 'claude-code-fixture-key\nargv-sentinel\n')
      if [ "$missing_key_output" != "$expected_missing_key_output" ]; then
        printf 'missing-key launch output mismatch: %s\n' "$missing_key_output" >&2
        exit 1
      fi

      preset_key_output=$("${pkgs.coreutils}/bin/env" -- \
        "$key_env=already-present-fixture-key" \
        "$spaced_env_name=argv-sentinel" \
        "$wrapper" -c ${lib.escapeShellArg printenvCommand} claude "$key_env" "$spaced_env_name")
      expected_preset_key_output=$(printf 'already-present-fixture-key\nargv-sentinel\n')
      if [ "$preset_key_output" != "$expected_preset_key_output" ]; then
        printf 'pre-set-key launch output mismatch: %s\n' "$preset_key_output" >&2
        exit 1
      fi

      touch "$out"
    '';
in
launcherCheck
