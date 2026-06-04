# Claude module regression tests
#
# The option schema and settings.json renderer live in nix-claude-code as
# of PR3. Byte-equivalence and settings-json structural validation are
# covered by `nix-claude-code/flake/checks.nix`. The checks here exercise
# nix-ai's user-facing claude-config.nix to catch drift on the values we
# actually override.
{ pkgs, hmConfig }:
let
  cfg = hmConfig.config.programs.claude;
in
{
  # Evaluate the real home-manager module with real inputs to catch import errors
  module-eval = builtins.seq hmConfig.activationPackage (
    pkgs.runCommand "check-module-eval" { } ''
      touch $out
    ''
  );

  # Verify expected option paths exist (catches accidentally dropped
  # options from the nix-claude-code-provided schema).
  options-regression =
    let
      expectedClaudeOptions = [
        "agents"
        "apiKeyHelper"
        "attribution"
        "commands"
        "effortLevel"
        "enable"
        "features"
        "hooks"
        "mcpServers"
        "model"
        "plugins"
        "remoteControlAtStartup"
        "rules"
        "settings"
        "showTurnDuration"
        "skills"
        "statusline"
        "teammateMode"
        "trustedProjectDirs"
      ];
      actualClaudeOptions = builtins.attrNames cfg;
      missingClaudeOptions = builtins.filter (
        o: !(builtins.elem o actualClaudeOptions)
      ) expectedClaudeOptions;

      expectedSettingsOptions = [
        "alwaysThinkingEnabled"
        "cleanupPeriodDays"
        "env"
        "permissions"
        "sandbox"
        "skillListingBudgetFraction"
        "skillOverrides"
      ];
      actualSettingsOptions = builtins.attrNames cfg.settings;
      missingSettingsOptions = builtins.filter (
        s: !(builtins.elem s actualSettingsOptions)
      ) expectedSettingsOptions;

      expectedHookOptions = [
        "postToolUse"
        "preToolUse"
        "sessionEnd"
        "sessionStart"
        "stop"
        "subagentStop"
        "userPromptSubmit"
      ];
      actualHookOptions = builtins.attrNames cfg.hooks;
      missingHookOptions = builtins.filter (h: !(builtins.elem h actualHookOptions)) expectedHookOptions;
    in
    assert
      missingClaudeOptions == [ ]
      || throw "Missing Claude options: ${builtins.toJSON missingClaudeOptions}";
    assert
      missingSettingsOptions == [ ]
      || throw "Missing settings options: ${builtins.toJSON missingSettingsOptions}";
    assert
      missingHookOptions == [ ] || throw "Missing hook options: ${builtins.toJSON missingHookOptions}";
    pkgs.runCommand "check-options-regression" { } ''
      echo "Option regression: ${toString (builtins.length expectedClaudeOptions)} Claude, ${toString (builtins.length expectedSettingsOptions)} settings, ${toString (builtins.length expectedHookOptions)} hooks verified"
      touch $out
    '';

  # Verify evaluated config values match expected values.
  # Tests claude-config.nix overrides against the schema's defaults.
  defaults-regression =
    let
      checks = [
        {
          name = "enable";
          actual = cfg.enable;
          expected = true;
        }
        {
          name = "alwaysThinkingEnabled";
          actual = cfg.settings.alwaysThinkingEnabled;
          expected = true;
        }
        {
          name = "cleanupPeriodDays";
          actual = cfg.settings.cleanupPeriodDays;
          expected = 180;
        }
        {
          name = "model";
          actual = cfg.model;
          expected = "default";
        }
        {
          name = "effortLevel";
          actual = cfg.effortLevel;
          expected = "high";
        }
        {
          name = "sandbox.enabled";
          actual = cfg.settings.sandbox.enabled;
          expected = false;
        }
        {
          name = "plugins.allowRuntimeInstall";
          actual = cfg.plugins.allowRuntimeInstall;
          expected = true;
        }
        {
          name = "remoteControlAtStartup";
          actual = cfg.remoteControlAtStartup;
          expected = true;
        }
        {
          name = "apiKeyHelper.enable";
          actual = cfg.apiKeyHelper.enable;
          expected = true;
        }
      ];
      failures = builtins.filter (c: c.actual != c.expected) checks;
      failureMsg = builtins.concatStringsSep "\n" (
        map (
          c: "  ${c.name}: expected ${builtins.toJSON c.expected}, got ${builtins.toJSON c.actual}"
        ) failures
      );
    in
    assert failures == [ ] || throw "Default value regression:\n${failureMsg}";
    pkgs.runCommand "check-defaults-regression" { } ''
      echo "Defaults regression: ${toString (builtins.length checks)} critical defaults verified"
      touch $out
    '';

  # Validate the maestro-cli script extraction produces correct output.
  # (Kept here for historical reasons — moves to maestro module checks long-term.)
  maestro-script =
    let
      testScript = pkgs.replaceVars ../../modules/maestro/scripts/maestro-cli.sh {
        maestroApp = "/test/path/to/Maestro";
      };
    in
    pkgs.runCommand "check-maestro-script" { } ''
      echo "Validating maestro-cli script..."

      # Verify @maestroApp@ placeholder was substituted
      if grep -q "@maestroApp@" ${testScript}; then
        echo "FAIL: @maestroApp@ placeholder was NOT substituted"
        exit 1
      fi

      # Verify the test path appears in the script
      if ! grep -q "/test/path/to/Maestro" ${testScript}; then
        echo "FAIL: substituted path not found in script"
        exit 1
      fi

      # Verify shebang
      if ! head -1 ${testScript} | grep -q "#!/usr/bin/env bash"; then
        echo "FAIL: missing or incorrect shebang"
        exit 1
      fi

      # Verify strict mode
      if ! grep -q "set -euo pipefail" ${testScript}; then
        echo "FAIL: missing set -euo pipefail"
        exit 1
      fi

      # Verify exec command is present
      if ! grep -q 'exec.*MAESTRO_APP' ${testScript}; then
        echo "FAIL: missing exec command"
        exit 1
      fi

      # Verify error handling exists
      if ! grep -q 'Maestro not found' ${testScript}; then
        echo "FAIL: missing error message"
        exit 1
      fi

      echo "Maestro script: substitution, shebang, strict mode, exec, error handling verified"
      touch $out
    '';
}
