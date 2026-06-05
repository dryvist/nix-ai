# Antigravity module regression tests
{ pkgs, hmConfig }:
let
  cfg = hmConfig.config.programs.antigravity-cli;
  homeFileNames = builtins.attrNames hmConfig.config.home.file;
in
{
  # Verify all expected Antigravity option paths exist.
  antigravity-cli-options-regression =
    let
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
        "sandbox"
        "sandboxAllowedPaths"
        "sandboxAllowedPathsMerged"
        "trustedFolders"
        "worktrees"
      ];
      actualOptions = builtins.attrNames cfg;
      missingOptions = builtins.filter (o: !(builtins.elem o actualOptions)) expectedOptions;
    in
    assert
      missingOptions == [ ] || throw "Missing Antigravity options: ${builtins.toJSON missingOptions}";
    pkgs.runCommand "check-antigravity-cli-options-regression" { } ''
      echo "Antigravity option regression: ${toString (builtins.length expectedOptions)} options verified"
      touch $out
    '';

  # Verify evaluated config values match expected defaults.
  antigravity-cli-defaults-regression =
    let
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
          expected = [ "AGENTS.md" ];
        }
        {
          name = "antigravity-cli.excludedMcpServers.length";
          actual = builtins.length cfg.excludedMcpServers;
          expected = 11;
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
      failures = builtins.filter (c: c.actual != c.expected) checks;
      failureMsg = builtins.concatStringsSep "\n" (
        map (
          c: "  ${c.name}: expected ${builtins.toJSON c.expected}, got ${builtins.toJSON c.actual}"
        ) failures
      );
    in
    assert failures == [ ] || throw "Antigravity default value regression:\n${failureMsg}";
    pkgs.runCommand "check-antigravity-cli-defaults-regression" { } ''
      echo "Antigravity defaults regression: ${toString (builtins.length checks)} critical defaults verified"
      touch $out
    '';

  # Validate activation package builds (forces settings.json generation).
  antigravity-cli-settings-json = builtins.seq hmConfig.activationPackage (
    pkgs.runCommand "check-antigravity-cli-settings-json" { } ''
      echo "Antigravity settings: activation package builds successfully (settings.json generation verified)"
      touch $out
    ''
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
    pkgs.runCommand "check-antigravity-cli-sandbox-default-paths" { } ''
      echo "Antigravity sandbox default: ${expected} is present in merged settings"
      touch $out
    '';

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
    pkgs.runCommand "check-antigravity-cli-module-loaded" { } ''
      echo "Antigravity module: .keep file present, module loaded successfully"
      touch $out
    '';

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
    pkgs.runCommand "check-antigravity-cli-policy-engine" { } ''
      echo "Antigravity Policy Engine: TOML structure verified (8 assertions: non-empty, [[rule]], 3 decision types, tool mappings, git rule)"
      touch $out
    '';
}
