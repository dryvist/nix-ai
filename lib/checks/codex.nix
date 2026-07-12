# Codex module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.codex;
  homeFileNames = builtins.attrNames hmConfig.config.home.file;
in
{
  # Verify all expected Codex option paths exist.
  codex-options-regression = helpers.mkOptionsRegression {
    label = "Codex";
    checkName = "check-codex-options-regression";
    inherit cfg;
    expectedOptions = [
      "approvalPolicy"
      "enable"
      "excludedMcpServers"
      "features"
      "hooks"
      "model"
      "modelProvider"
      "modelReasoningEffort"
      "modelVerbosity"
      "mcpServerNames"
      "planModeReasoningEffort"
      "projectDocFallbackFilenames"
      "reviewModel"
      "serviceTier"
      "trustedProjectDirs"
      "webSearch"
    ];
  };

  # Verify evaluated config values match expected defaults.
  codex-defaults-regression = helpers.mkDefaultsRegression {
    label = "Codex";
    checkName = "check-codex-defaults-regression";
    checks = [
      {
        name = "codex.enable";
        actual = cfg.enable;
        expected = true;
      }
      {
        name = "codex.approvalPolicy";
        actual = cfg.approvalPolicy;
        expected = "untrusted";
      }
      {
        name = "codex.features";
        actual = cfg.features;
        expected = { };
      }
      {
        name = "codex.model";
        actual = cfg.model;
        expected = null;
      }
      {
        name = "codex.modelProvider";
        actual = cfg.modelProvider;
        expected = null;
      }
      {
        name = "codex.modelReasoningEffort";
        actual = cfg.modelReasoningEffort;
        expected = "medium";
      }
      {
        name = "codex.modelVerbosity";
        actual = cfg.modelVerbosity;
        expected = "medium";
      }
      {
        name = "codex.planModeReasoningEffort";
        actual = cfg.planModeReasoningEffort;
        expected = "high";
      }
      {
        name = "codex.reviewModel";
        actual = cfg.reviewModel;
        expected = null;
      }
      {
        name = "codex.serviceTier";
        actual = cfg.serviceTier;
        expected = null;
      }
      {
        name = "codex.webSearch";
        actual = cfg.webSearch;
        expected = null;
      }
      {
        name = "codex.excludedMcpServers.length";
        actual = builtins.length cfg.excludedMcpServers;
        expected = 0;
      }
      {
        name = "codex.trustedProjectDirs";
        actual = cfg.trustedProjectDirs;
        expected = [ ];
      }
      {
        name = "codex.projectDocFallbackFilenames";
        actual = cfg.projectDocFallbackFilenames;
        expected = [ "AGENTS.md" ];
      }
      {
        name = "codex.hooks.notification";
        actual = cfg.hooks.notification;
        expected = null;
      }
    ];
  };

  # Validate the activation package builds (forces config.toml generation).
  codex-settings-toml = builtins.seq hmConfig.activationPackage (
    let
      disallowedCodexFiles = builtins.filter (n: n == "GEMINI.md") homeFileNames;
    in
    assert
      disallowedCodexFiles == [ ]
      || throw "Codex must not deploy tool-specific shared skills or GEMINI.md: ${builtins.toJSON disallowedCodexFiles}";
    helpers.mkMarker "check-codex-settings-toml" "Codex settings: activation package builds successfully (config.toml generation verified)"
  );

  # Validate permissions pipeline produces non-empty rules via home.file output.
  codex-permissions =
    let
      # Extract the generated rules text from the evaluated home.file entries.
      # Path matches configDir computation in settings.nix (non-XDG default for test env).
      rulesText = hmConfig.config.home.file.".codex/rules/default.rules".text;
    in
    pkgs.runCommand "check-codex-permissions"
      {
        nativeBuildInputs = [ pkgs.gnugrep ];
        passAsFile = [ "rules" ];
        rules = rulesText;
      }
      ''
        echo "Validating Codex permissions pipeline..."

        # Rules file must be non-empty
        if [ ! -s "$rulesPath" ]; then
          echo "FAIL: codex rules file is empty"
          exit 1
        fi

        # Must contain prefix_rule entries
        if ! grep -q "prefix_rule" "$rulesPath"; then
          echo "FAIL: no prefix_rule entries found"
          exit 1
        fi

        # Must contain both allow and forbidden rules
        if ! grep -q '"allow"' "$rulesPath"; then
          echo "FAIL: no allow rules found"
          exit 1
        fi
        if ! grep -q '"forbidden"' "$rulesPath"; then
          echo "FAIL: no forbidden rules found"
          exit 1
        fi

        # Deny rules must appear before allow rules (line numbers)
        # Use grep -m1 instead of grep | head -1 to avoid SIGPIPE on Linux
        FIRST_DENY=$(grep -m1 -n '"forbidden"' "$rulesPath" | cut -d: -f1)
        FIRST_ALLOW=$(grep -m1 -n '"allow"' "$rulesPath" | cut -d: -f1)
        if [ "$FIRST_DENY" -gt "$FIRST_ALLOW" ]; then
          echo "FAIL: deny rules should appear before allow rules"
          exit 1
        fi

        echo "Codex permissions: rules file non-empty, prefix_rule entries present, deny-before-allow ordering verified"
        touch $out
      '';
}
