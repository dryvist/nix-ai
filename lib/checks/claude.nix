# Claude module regression tests and pure generators
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

  # Verify all expected option paths exist in the evaluated module.
  # Catches accidentally dropped options (e.g., from refactoring with lib;).
  options-regression =
    let
      expectedClaudeOptions = [
        "agents"
        "apiKeyHelper"
        "attribution"
        "autoUpdatesChannel"
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
        "statusLine"
        "teammateMode"
        "trustedProjectDirs"
      ];
      actualClaudeOptions = builtins.attrNames cfg;
      missingClaudeOptions = builtins.filter (
        o: !(builtins.elem o actualClaudeOptions)
      ) expectedClaudeOptions;

      expectedSettingsOptions = [
        "additionalDirectories"
        "alwaysThinkingEnabled"
        "cleanupPeriodDays"
        "env"
        "permissions"
        "sandbox"
        "schemaUrl"
        "skillListingBudgetFraction"
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

      expectedPermissionOptions = [
        "allow"
        "ask"
        "defaultMode"
        "deny"
      ];
      actualPermissionOptions = builtins.attrNames cfg.settings.permissions;
      missingPermissionOptions = builtins.filter (
        p: !(builtins.elem p actualPermissionOptions)
      ) expectedPermissionOptions;

      expectedSandboxOptions = [
        "autoAllowBashIfSandboxed"
        "enabled"
        "excludedCommands"
      ];
      actualSandboxOptions = builtins.attrNames cfg.settings.sandbox;
      missingSandboxOptions = builtins.filter (
        s: !(builtins.elem s actualSandboxOptions)
      ) expectedSandboxOptions;
    in
    assert
      missingClaudeOptions == [ ]
      || throw "Missing Claude options: ${builtins.toJSON missingClaudeOptions}";
    assert
      missingSettingsOptions == [ ]
      || throw "Missing settings options: ${builtins.toJSON missingSettingsOptions}";
    assert
      missingHookOptions == [ ] || throw "Missing hook options: ${builtins.toJSON missingHookOptions}";
    assert
      missingPermissionOptions == [ ]
      || throw "Missing permission options: ${builtins.toJSON missingPermissionOptions}";
    assert
      missingSandboxOptions == [ ]
      || throw "Missing sandbox options: ${builtins.toJSON missingSandboxOptions}";
    pkgs.runCommand "check-options-regression" { } ''
      echo "Option regression: ${toString (builtins.length expectedClaudeOptions)} Claude, ${toString (builtins.length expectedSettingsOptions)} settings, ${toString (builtins.length expectedHookOptions)} hooks, ${toString (builtins.length expectedPermissionOptions)} permissions, ${toString (builtins.length expectedSandboxOptions)} sandbox options verified"
      touch $out
    '';

  # Verify evaluated config values match expected values.
  # Tests the FULL module output (options.nix defaults + claude-config.nix overrides).
  # Catches unintended changes to either file.
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
          expected = 30;
        }
        {
          name = "skillListingBudgetFraction";
          actual = cfg.settings.skillListingBudgetFraction;
          expected = 0.03;
        }
        {
          name = "autoUpdatesChannel";
          actual = cfg.autoUpdatesChannel;
          expected = "latest";
        }
        {
          name = "teammateMode";
          actual = cfg.teammateMode;
          expected = "auto";
        }
        {
          name = "showTurnDuration";
          actual = cfg.showTurnDuration;
          expected = false;
        }
        {
          name = "model";
          actual = cfg.model;
          expected = "opusplan";
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
          name = "sandbox.autoAllowBashIfSandboxed";
          actual = cfg.settings.sandbox.autoAllowBashIfSandboxed;
          expected = true;
        }
        {
          name = "statusLine.enable";
          actual = cfg.statusLine.enable;
          expected = true;
        }
        {
          name = "schemaUrl";
          actual = cfg.settings.schemaUrl;
          expected = "https://json.schemastore.org/claude-code-settings.json";
        }
        {
          name = "plugins.allowRuntimeInstall";
          actual = cfg.plugins.allowRuntimeInstall;
          expected = true;
        }
        {
          name = "features.pluginSchemaVersion";
          actual = cfg.features.pluginSchemaVersion;
          expected = 1;
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
        {
          name = "settings.permissions.defaultMode";
          actual = cfg.settings.permissions.defaultMode;
          expected = "auto";
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

  # Validate the pure settings JSON generator (lib/claude-settings.nix).
  # Verifies structure, required keys, types, and value correctness.
  settings-json =
    let
      ciSettings = import ../claude-settings.nix {
        inherit (pkgs) lib;
        homeDir = "/home/test-user";
        schemaUrl = "https://json.schemastore.org/claude-code-settings.json";
        permissions = {
          allow = [
            "Read"
            "Write"
          ];
          deny = [ "Bash(rm -rf /)" ];
          ask = [ ];
        };
        plugins = {
          marketplaces = { };
          enabledPlugins = { };
        };
        additionalDirectories = [ "~/.claude/" ]; # CI fixture — real list in modules/claude-config.nix
      };
    in
    pkgs.runCommand "check-settings-json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        passAsFile = [ "json" ];
        json = builtins.toJSON ciSettings;
      }
      ''
        echo "Validating settings JSON structure..."

        # Verify required keys exist
        jq -e 'has("$schema")' "$jsonPath" > /dev/null || { echo "FAIL: missing \$schema"; exit 1; }
        jq -e 'has("alwaysThinkingEnabled")' "$jsonPath" > /dev/null || { echo "FAIL: missing alwaysThinkingEnabled"; exit 1; }
        jq -e 'has("permissions")' "$jsonPath" > /dev/null || { echo "FAIL: missing permissions"; exit 1; }
        jq -e 'has("extraKnownMarketplaces")' "$jsonPath" > /dev/null || { echo "FAIL: missing extraKnownMarketplaces"; exit 1; }
        jq -e 'has("enabledPlugins")' "$jsonPath" > /dev/null || { echo "FAIL: missing enabledPlugins"; exit 1; }
        jq -e 'has("statusLine")' "$jsonPath" > /dev/null || { echo "FAIL: missing statusLine"; exit 1; }

        # Verify permission structure
        jq -e '.permissions | has("allow")' "$jsonPath" > /dev/null || { echo "FAIL: missing permissions.allow"; exit 1; }
        jq -e '.permissions | has("deny")' "$jsonPath" > /dev/null || { echo "FAIL: missing permissions.deny"; exit 1; }
        jq -e '.permissions | has("ask")' "$jsonPath" > /dev/null || { echo "FAIL: missing permissions.ask"; exit 1; }
        jq -e '.permissions | has("additionalDirectories")' "$jsonPath" > /dev/null || { echo "FAIL: missing permissions.additionalDirectories"; exit 1; }
        jq -e '.permissions.defaultMode == "auto"' "$jsonPath" > /dev/null || { echo "FAIL: permissions.defaultMode not \"auto\""; exit 1; }

        # Verify types (only for fields without a value assertion)
        jq -e '.permissions.additionalDirectories | type == "array"' "$jsonPath" > /dev/null || { echo "FAIL: additionalDirectories not array"; exit 1; }
        jq -e '.extraKnownMarketplaces | type == "object"' "$jsonPath" > /dev/null || { echo "FAIL: extraKnownMarketplaces not object"; exit 1; }

        # Verify values
        jq -e '."$schema" == "https://json.schemastore.org/claude-code-settings.json"' "$jsonPath" > /dev/null || { echo "FAIL: wrong schema URL"; exit 1; }
        jq -e '.alwaysThinkingEnabled == true' "$jsonPath" > /dev/null || { echo "FAIL: alwaysThinkingEnabled should be true"; exit 1; }
        jq -e '.permissions.allow | length == 2' "$jsonPath" > /dev/null || { echo "FAIL: expected 2 allow entries"; exit 1; }
        jq -e '.permissions.deny | length == 1' "$jsonPath" > /dev/null || { echo "FAIL: expected 1 deny entry"; exit 1; }
        jq -e '.permissions.ask | length == 0' "$jsonPath" > /dev/null || { echo "FAIL: expected 0 ask entries"; exit 1; }
        jq -e '.statusLine.type == "command"' "$jsonPath" > /dev/null || { echo "FAIL: statusLine.type should be command"; exit 1; }

        echo "Settings JSON: 6 keys, 5 permission fields, 2 type checks, 6 value checks passed"
        touch $out
      '';

  # Validate the maestro-cli script extraction produces correct output.
  # Builds the script via pkgs.substituteAll and verifies content integrity.
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
