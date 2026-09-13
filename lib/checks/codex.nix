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
      "otelExporterKinds"
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
        expected = "never";
      }
      {
        # `hooks` is on because programs.herdr.integrations names codex: Codex
        # reads ~/.codex/hooks.json only behind this flag, so herdr's lifecycle
        # hook is inert without it.
        name = "codex.features";
        actual = cfg.features;
        expected = {
          hooks = true;
        };
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
      {
        # Both exporters pinned off by default (no telemetry configured in the
        # base test fixture) — never left unset, since Codex's own unset
        # default is Statsig, not "nothing".
        name = "codex.otelExporterKinds (telemetry unconfigured)";
        actual = cfg.otelExporterKinds;
        expected = {
          trace = "none";
          metrics = "none";
        };
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

  codex-zai-profile =
    let
      profile = hmConfig.config.home.file.".codex/zai.config.toml".source;
      catalog = hmConfig.config.home.file.".codex/zai-models.json".text;
    in
    pkgs.runCommand "check-codex-zai-profile"
      {
        nativeBuildInputs = [ pkgs.jq ];
        passAsFile = [ "catalog" ];
        inherit catalog;
      }
      ''
        jq -e '
          .models == [{
            slug: "glm-5.3",
            display_name: "glm-5.3",
            description: "Z.ai flagship coding model",
            default_reasoning_level: "max",
            supported_reasoning_levels: [
              { effort: "low", description: "Light reasoning" },
              { effort: "high", description: "Enhanced reasoning" },
              { effort: "max", description: "Deep reasoning" }
            ],
            shell_type: "shell_command",
            visibility: "list",
            supported_in_api: true,
            priority: 0,
            base_instructions: "",
            supports_reasoning_summaries: true,
            default_reasoning_summary: "none",
            support_verbosity: false,
            apply_patch_tool_type: "freeform",
            truncation_policy: { mode: "bytes", limit: 10000 },
            context_window: 1048576,
            max_context_window: 1048576,
            effective_context_window_percent: 50,
            supports_parallel_tool_calls: true,
            experimental_supported_tools: [],
            input_modalities: ["text"]
          }]
        ' "$catalogPath" >/dev/null

        grep -Fq 'model = "glm-5.3"' ${profile}
        grep -Fq 'model_provider = "ZAI"' ${profile}
        grep -Fq 'model_reasoning_effort = "max"' ${profile}
        grep -Fq 'model_catalog_json = "/home/test-user/.codex/zai-models.json"' ${profile}
        grep -Fq 'base_url = "https://api.z.ai/api/v1"' ${profile}
        grep -Fq 'env_key = "ZAI_SUBSCRIPTION_KEY"' ${profile}
        grep -Fq 'wire_api = "responses"' ${profile}
        if grep -Fq 'experimental_bearer_token' ${profile}; then
          echo "FAIL: Z.ai credential must be read from env_key, never rendered into TOML" >&2
          exit 1
        fi
        touch $out
      '';

  zai-launchers =
    pkgs.runCommand "check-zai-launchers"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.zsh
        ];
      }
      ''
        ${pkgs.bash}/bin/bash ${./scripts/zai-launchers-test.sh} ${../../modules/ai-aliases.zsh}
        touch $out
      '';
}
