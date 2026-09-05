# Cursor CLI module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.cursor;
  nixpkgsCursorCli = pkgs.cursor-cli;
in
{
  # Verify all expected Cursor option paths exist.
  cursor-options-regression = helpers.mkOptionsRegression {
    label = "Cursor";
    checkName = "check-cursor-options-regression";
    inherit cfg;
    expectedOptions = [
      "approvalMode"
      "enable"
      "excludedMcpServers"
      "extraSettings"
      "mcpServerNames"
      "vimMode"
    ];
  };

  # Verify evaluated config values match expected defaults.
  cursor-defaults-regression = helpers.mkDefaultsRegression {
    label = "Cursor";
    checkName = "check-cursor-defaults-regression";
    checks = [
      {
        name = "cursor.enable";
        actual = cfg.enable;
        expected = true;
      }
      {
        name = "cursor.vimMode";
        actual = cfg.vimMode;
        expected = false;
      }
      {
        name = "cursor.approvalMode";
        actual = cfg.approvalMode;
        expected = "allowlist";
      }
    ];
  };

  # Assert exactly one cursor-cli derivation in home.packages, and that it is
  # the nixpkgs package rather than a vendored copy. A second cursor-cli in the
  # profile is the dual-install bug this module exists to prevent; a vendored
  # derivation was tried and reverted, because nixpkgs already ships this
  # package with its own updateScript.
  cursor-ownership-regression = helpers.mkDefaultsRegression {
    label = "Cursor ownership";
    checkName = "check-cursor-ownership-regression";
    checks =
      let
        # Derivations in home.packages have 'name' (full) and 'pname' (package name)
        # Use hasAttr to safely check for pname
        isCursorCli = p: builtins.hasAttr "pname" p && p.pname == "cursor-cli";
        cursorPkgs = builtins.filter isCursorCli hmConfig.config.home.packages;
        cursorPkg = builtins.head cursorPkgs;
      in
      [
        {
          name = "exactly one cursor-cli in home.packages";
          actual = builtins.length cursorPkgs;
          expected = 1;
        }
        {
          name = "cursor-cli is the nixpkgs package, not a vendored copy";
          actual = cursorPkg.drvPath == nixpkgsCursorCli.drvPath;
          expected = true;
        }
      ];
  };

  # Assert the two ~/.local/bin names are declared with force = true, and
  # that mcp.json + cursorConfigMerge are conserved. force is the whole
  # mechanism: without it home-manager refuses to replace the real files the
  # self-updater leaves behind, and activation fails instead of reclaiming
  # the names.
  cursor-reclaim-data = helpers.mkDefaultsRegression {
    label = "Cursor reclaim data";
    checkName = "check-cursor-reclaim-data";
    checks =
      let
        files = hmConfig.config.home.file;
        homeFileNames = builtins.attrNames files;
        agentBin = "${nixpkgsCursorCli}/bin/cursor-agent";
      in
      [
        {
          name = "home.file declares .local/bin/agent";
          actual = builtins.elem ".local/bin/agent" homeFileNames;
          expected = true;
        }
        {
          name = "home.file declares .local/bin/cursor-agent";
          actual = builtins.elem ".local/bin/cursor-agent" homeFileNames;
          expected = true;
        }
        {
          name = ".local/bin/agent is forced";
          actual = files.".local/bin/agent".force;
          expected = true;
        }
        {
          name = ".local/bin/cursor-agent is forced";
          actual = files.".local/bin/cursor-agent".force;
          expected = true;
        }
        {
          name = ".local/bin/agent points at the cursor-cli binary";
          actual = toString files.".local/bin/agent".source;
          expected = agentBin;
        }
        {
          name = ".local/bin/cursor-agent points at the cursor-cli binary";
          actual = toString files.".local/bin/cursor-agent".source;
          expected = agentBin;
        }
        {
          name = "no bespoke reclaim activation script remains";
          actual = hmConfig.config.home.activation ? cursorAgentReclaim;
          expected = false;
        }
        {
          name = "home.file still declares .cursor/mcp.json (conservation)";
          actual = builtins.elem ".cursor/mcp.json" homeFileNames;
          expected = true;
        }
        {
          name = "cursorConfigMerge activation still exists (conservation)";
          actual = hmConfig.config.home.activation ? cursorConfigMerge;
          expected = true;
        }
      ];
  };

  cursor-activation-regression = helpers.mkDefaultsRegression {
    label = "Cursor activation";
    checkName = "check-cursor-activation-regression";
    checks = [
      {
        name = "cursor.configMerge activation present";
        actual = hmConfig.config.home.activation ? cursorConfigMerge;
        expected = true;
      }
    ];
  };
}
