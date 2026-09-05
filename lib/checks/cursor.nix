# Cursor CLI module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.cursor;

  # The release channel's build. Referenced only to assert the module is NOT
  # using it — see cursor-ownership-regression.
  releaseChannelCursorCli = pkgs.cursor-cli;

  # The cursor-cli the module actually installs. Taken from the evaluated
  # config rather than recomputed, so the link assertions below prove the
  # links point at the installed derivation whatever channel supplies it.
  installedCursorCli = builtins.head (
    builtins.filter (
      p: builtins.hasAttr "pname" p && p.pname == "cursor-cli"
    ) hmConfig.config.home.packages
  );
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

  # Assert exactly one cursor-cli derivation in home.packages, and that it comes
  # from nixpkgs-unstable rather than the pinned release channel. A second
  # cursor-cli in the profile is the dual-install bug this module exists to
  # prevent; a vendored derivation was tried and reverted, because nixpkgs
  # already ships this package with its own updateScript.
  #
  # The channel assertion exists because the failure is silent: 26.05-darwin
  # froze cursor-cli at 2026.05.16 and kept evaluating green, so the profile
  # shipped a months-old agent CLI with nothing to indicate it. Comparing
  # against `pkgs.cursor-cli` — the release-channel build — makes a silent
  # fall-back to the frozen version a red check.
  #
  # This proves the SOURCE, not the freshness. Nix evaluation is pure and has no
  # clock, so "is this build recent" cannot be asserted here; that is the
  # weekly relock's job (deps-flake-lock.yml moves both channels together).
  cursor-ownership-regression = helpers.mkDefaultsRegression {
    label = "Cursor ownership";
    checkName = "check-cursor-ownership-regression";
    checks =
      let
        # Derivations in home.packages have 'name' (full) and 'pname' (package name)
        # Use hasAttr to safely check for pname
        isCursorCli = p: builtins.hasAttr "pname" p && p.pname == "cursor-cli";
        cursorPkgs = builtins.filter isCursorCli hmConfig.config.home.packages;
      in
      [
        {
          name = "exactly one cursor-cli in home.packages";
          actual = builtins.length cursorPkgs;
          expected = 1;
        }
        {
          name = "cursor-cli is not the frozen release-channel build";
          actual = installedCursorCli.drvPath == releaseChannelCursorCli.drvPath;
          expected = false;
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
        agentBin = "${installedCursorCli}/bin/cursor-agent";
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
