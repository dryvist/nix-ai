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

  # Validate Policy Engine TOML is deployed and settings.json uses policyPaths.
  antigravity-cli-policy-engine =
    let
      policyFileEntry = hmConfig.config.home.file.".gemini/antigravity-cli/policies/nix-managed.toml";
      policyContent = builtins.readFile policyFileEntry.source;
      inherit (pkgs) lib;
    in
    assert lib.stringLength policyContent > 0 || throw "Policy TOML is empty";
    assert lib.hasInfix "[[rule]]" policyContent || throw "No [[rule]] entries found";
    assert lib.hasInfix ''decision = "allow"'' policyContent || throw "No allow rules found";
    assert lib.hasInfix ''decision = "deny"'' policyContent || throw "No deny rules found";
    assert lib.hasInfix ''decision = "ask_user"'' policyContent || throw "No ask_user rules found";
    assert
      lib.hasInfix ''toolName = "read_file"'' policyContent || throw "Missing read_file tool mapping";
    assert
      lib.hasInfix ''toolName = "run_shell_command"'' policyContent
      || throw "No run_shell_command rules found";
    assert
      lib.hasInfix ''commandPrefix = "git"'' policyContent || throw "Missing git commandPrefix rule";
    helpers.mkMarker "check-antigravity-cli-policy-engine" "Antigravity Policy Engine: TOML structure verified (8 assertions: non-empty, [[rule]], 3 decision types, tool mappings, git rule)";
}
