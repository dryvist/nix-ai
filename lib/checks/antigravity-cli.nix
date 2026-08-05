# Antigravity module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.antigravity-cli;
  homeFileNames = builtins.attrNames hmConfig.config.home.file;
in
{
  # Verify all expected Antigravity option paths exist.
  antigravity-cli-options-regression = helpers.mkOptionsRegression {
    label = "Antigravity";
    checkName = "check-antigravity-cli-options-regression";
    inherit cfg;
    expectedOptions = [
      "commands"
      "contextFileNames"
      "defaultApprovalMode"
      "defaultModel"
      "enable"
      "excludedMcpServers"
      "extensions"
      "gemmaModelRouter"
      "hooks"
      "mcpServerNames"
      "policyRules"
      "sandbox"
      "sandboxAllowedPaths"
      "sandboxAllowedPathsMerged"
      "trustedFolders"
      "worktrees"
    ];
  };

  # Verify evaluated config values match expected defaults.
  antigravity-cli-defaults-regression = helpers.mkDefaultsRegression {
    label = "Antigravity";
    checkName = "check-antigravity-cli-defaults-regression";
    checks = [
      {
        name = "antigravity-cli.enable";
        actual = cfg.enable;
        expected = true;
      }
      {
        name = "antigravity-cli.trustedFolders";
        actual = cfg.trustedFolders;
        expected = [ ];
      }
      {
        name = "antigravity-cli.contextFileNames";
        actual = cfg.contextFileNames;
        expected = [
          "AGENTS.md"
          "AGENTS.local.md"
        ];
      }
      {
        name = "antigravity-cli.excludedMcpServers.length";
        actual = builtins.length cfg.excludedMcpServers;
        expected = 0;
      }
      {
        name = "antigravity-cli.extensions";
        actual = cfg.extensions;
        expected = { };
      }
      {
        name = "antigravity-cli.hooks.beforeTool";
        actual = cfg.hooks.beforeTool;
        expected = null;
      }
      {
        name = "antigravity-cli.hooks.afterTool";
        actual = cfg.hooks.afterTool;
        expected = null;
      }
      {
        name = "antigravity-cli.commands.fromFlakeInputs";
        actual = cfg.commands.fromFlakeInputs;
        expected = [ ];
      }
      {
        name = "antigravity-cli.commands.local";
        actual = cfg.commands.local;
        expected = { };
      }
      {
        name = "antigravity-cli.sandbox.enable";
        actual = cfg.sandbox.enable;
        expected = true;
      }
      {
        name = "antigravity-cli.sandbox.profile";
        actual = cfg.sandbox.profile;
        expected = null;
      }
      {
        name = "antigravity-cli.sandboxAllowedPaths";
        actual = cfg.sandboxAllowedPaths;
        expected = [ ];
      }
      {
        name = "antigravity-cli.defaultModel";
        actual = cfg.defaultModel;
        expected = null;
      }
      {
        name = "antigravity-cli.gemmaModelRouter.enable";
        actual = cfg.gemmaModelRouter.enable;
        expected = false;
      }
      {
        name = "antigravity-cli.gemmaModelRouter.autoStartServer";
        actual = cfg.gemmaModelRouter.autoStartServer;
        expected = false;
      }
      {
        name = "antigravity-cli.gemmaModelRouter.port";
        actual = cfg.gemmaModelRouter.port;
        expected = 9379;
      }
      {
        name = "antigravity-cli.gemmaModelRouter.binaryPath";
        actual = cfg.gemmaModelRouter.binaryPath;
        expected = "";
      }
      {
        name = "antigravity-cli.gemmaModelRouter.classifierModel";
        actual = cfg.gemmaModelRouter.classifierModel;
        expected = "gemma3-1b-gpu-custom";
      }
    ];
  };

  # Validate activation package builds (forces settings.json generation).
  antigravity-cli-settings-json = builtins.seq hmConfig.activationPackage (
    helpers.mkMarker "check-antigravity-cli-settings-json" "Antigravity settings: activation package builds successfully (settings.json generation verified)"
  );

  # Validate that the evaluated settings always include the `~/git` sandbox
  # default (what actually lands in `tools.sandboxAllowedPaths` in settings.json).
  # Reads the read-only `sandboxAllowedPathsMerged` option the settings module
  # populates, so a broken merge fails the check at eval time.
  antigravity-cli-sandbox-default-paths =
    let
      expected = "${hmConfig.config.home.homeDirectory}/git";
      merged = hmConfig.config.programs.antigravity-cli.sandboxAllowedPathsMerged;
      hasGitDir = builtins.elem expected merged;
    in
    assert
      hasGitDir
      || throw "Antigravity sandboxAllowedPathsMerged missing ${expected}: ${builtins.toJSON merged}";
    helpers.mkMarker "check-antigravity-cli-sandbox-default-paths" "Antigravity sandbox default: ${expected} is present in merged settings";

  # Validate the .gemini/antigravity-cli/.keep directory marker is created (proves module loaded).
  antigravity-cli-module-loaded =
    let
      keepFile = hmConfig.config.home.file.".gemini/antigravity-cli/.keep".text;
      disallowedAntigravityFiles = builtins.filter (
        n:
        n == "GEMINI.md"
        || builtins.match "^\\.gemini/antigravity-cli/skills/.+$" n != null
        || builtins.match "^\\.gemini/antigravity-cli/extensions/[^/]+/skills/.+$" n != null
      ) homeFileNames;
    in
    assert keepFile != "" || throw "Antigravity .keep file is empty (module not loaded)";
    assert
      disallowedAntigravityFiles == [ ]
      || throw "Antigravity must not deploy skills or GEMINI.md: ${builtins.toJSON disallowedAntigravityFiles}";
    helpers.mkMarker "check-antigravity-cli-module-loaded" "Antigravity module: .keep file present, module loaded successfully";

  # Validate the Policy Engine rules and that the TOML is deployed.
  #
  # Asserts on cfg.policyRules — the Nix list that becomes the TOML's `rule`
  # array — instead of reading the generated file back. Reading it back was
  # import-from-derivation, which `nix flake check --no-build` cannot satisfy;
  # it failed with "path '<hash>-antigravity-policy.toml.drv' is not valid".
  # Because the scheduled relock workflow validates with that exact flag, the
  # failure took every weekly nixpkgs relock with it (2026-07-28, 2026-08-03),
  # leaving both channels ~1 month stale and llama-swap pinned at v224 while
  # upstream shipped v247. That workflow is now deps-flake-lock.yml, which
  # still runs `nix flake check --no-build` — so keep this check IFD-free.
  #
  # Asserting on the attrset is also stricter: typed field lookups replace
  # substring matches, so text that merely appeared somewhere in the rendered
  # TOML can no longer satisfy a rule assertion.
  antigravity-cli-policy-engine =
    let
      inherit (pkgs) lib;
      execToolName = "run_shell_command";
      rules = cfg.policyRules;
      decisions = map (r: r.decision or null) rules;
      toolNames = map (r: r.toolName or null) rules;
      prefixes = builtins.filter (p: p != null) (map (r: r.commandPrefix or null) rules);
      # Assert the file is still deployed WITHOUT forcing its source
      # derivation — forcing it is the import-from-derivation this removes.
      policyDeployed = hmConfig.config.home.file ? ".gemini/antigravity-cli/policies/nix-managed.toml";
    in
    assert lib.assertMsg (builtins.length rules > 0) "Policy rules list is empty";
    assert lib.assertMsg policyDeployed "nix-managed.toml is not deployed via home.file";
    assert lib.assertMsg (builtins.elem "allow" decisions) "No allow rules found";
    assert lib.assertMsg (builtins.elem "deny" decisions) "No deny rules found";
    assert lib.assertMsg (
      !builtins.elem "ask_user" decisions
    ) "ask_user rules present — the two-tier model renders allow/deny only";
    assert lib.assertMsg (builtins.elem "read_file" toolNames) "Missing read_file tool mapping";
    assert lib.assertMsg (builtins.elem execToolName toolNames) "No ${execToolName} rules found";
    assert lib.assertMsg (builtins.elem "git" prefixes) "Missing git commandPrefix rule";
    helpers.mkMarker "check-antigravity-cli-policy-engine" "Antigravity Policy Engine: rules verified on the Nix attrset, no import-from-derivation (8 assertions: non-empty, file deployed, allow/deny present, ask_user absent, tool mappings, git prefix)";
}
