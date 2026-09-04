# Cursor CLI module regression tests
{ pkgs, hmConfig, cursorCliPkg }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.cursor;
  versions = import ../../lib/versions.nix;
  cursorCliPin = versions.cursorCli;
  # The frozen nixpkgs-26.05 cursor-cli package (for drift detection)
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

  # Assert exactly one cursor-cli derivation in home.packages, with the
  # correct pinned version, NOT the frozen nixpkgs-26.05 package, and the
  # pin matches the lab shape (YYYY.MM.DD-shortHash).
  cursor-ownership-regression = helpers.mkDefaultsRegression {
    label = "Cursor ownership";
    checkName = "check-cursor-ownership-regression";
    checks = let
      # Derivations in home.packages have 'name' (full) and 'pname' (package name)
      # Use hasAttr to safely check for pname
      isCursorCli = p: builtins.hasAttr "pname" p && p.pname == "cursor-cli";
      cursorPkgs = builtins.filter isCursorCli hmConfig.config.home.packages;
      cursorPkg = builtins.head cursorPkgs;
      pinShape = "^2026\\.[0-9]{2}\\.[0-9]{2}-[a-f0-9]+$";
    in [
      {
        name = "exactly one cursor-cli in home.packages";
        actual = builtins.length cursorPkgs;
        expected = 1;
      }
      {
        name = "cursor-cli version matches lib/versions.nix pin";
        actual = cursorPkg.version;
        expected = cursorCliPin;
      }
      {
        name = "cursor-cli is NOT the frozen nixpkgs-26.05 package";
        actual = cursorPkg.drvPath != nixpkgsCursorCli.drvPath;
        expected = true;
      }
      {
        name = "cursor-cli pin matches lab shape YYYY.MM.DD-shortHash";
        actual = builtins.match pinShape cursorCliPin != null;
        expected = true;
      }
    ];
  };

  # Assert the reclaim activation data references the store binary, the
  # obsolete home.file symlinks are gone, and mcp.json + cursorConfigMerge
  # are conserved.
  cursor-reclaim-data = helpers.mkDefaultsRegression {
    label = "Cursor reclaim data";
    checkName = "check-cursor-reclaim-data";
    checks = let
      reclaimData = hmConfig.config.home.activation.cursorAgentReclaim.data or "";
      isCursorCli = p: builtins.hasAttr "pname" p && p.pname == "cursor-cli";
      ownerPkg = builtins.head (builtins.filter isCursorCli hmConfig.config.home.packages);
      expectedStorePath = "${ownerPkg}/bin/cursor-agent";
      hasStorePath = pkgs.lib.hasInfix expectedStorePath reclaimData;
      homeFileNames = builtins.attrNames hmConfig.config.home.file;
      hasAgentLink = builtins.elem ".local/bin/agent" homeFileNames;
      hasCursorAgentLink = builtins.elem ".local/bin/cursor-agent" homeFileNames;
      hasMcpJson = builtins.elem ".cursor/mcp.json" homeFileNames;
      hasConfigMerge = hmConfig.config.home.activation ? cursorConfigMerge;
    in [
      {
        name = "reclaim activation data references store binary";
        actual = hasStorePath;
        expected = true;
      }
      {
        name = "home.file no longer declares .local/bin/agent";
        actual = hasAgentLink;
        expected = false;
      }
      {
        name = "home.file no longer declares .local/bin/cursor-agent";
        actual = hasCursorAgentLink;
        expected = false;
      }
      {
        name = "home.file still declares .cursor/mcp.json (conservation)";
        actual = hasMcpJson;
        expected = true;
      }
      {
        name = "cursorConfigMerge activation still exists (conservation)";
        actual = hasConfigMerge;
        expected = true;
      }
    ];
  };

  # Behavioral sandbox check: drives the reclaim script against a temporary
  # home for the five filesystem cases (absent, regular file, symlink,
  # idempotent rerun, real-directory rejection). Must actually execute and
  # pass on the Linux runner.
  cursor-reclaim-sandbox = pkgs.runCommand "check-cursor-reclaim-sandbox" {
    nativeBuildInputs = [ pkgs.coreutils pkgs.bash ];
  } ''
    set -euo pipefail

    RECLAIM_SCRIPT="${../../modules/scripts/cursor-reclaim-links.sh}"
    NIX_BINARY="${cursorCliPkg}/bin/cursor-agent"

    # Create a temporary home directory
    TMP_HOME=$(mktemp -d)
    TARGET_DIR="$TMP_HOME/.local/bin"
    mkdir -p "$TARGET_DIR"

    echo "[SANDBOX] Testing reclaim script against $TARGET_DIR"

    # Case 1: Absent -> symlink created
    "$RECLAIM_SCRIPT" "$NIX_BINARY" "$TARGET_DIR"
    if [[ ! -L "$TARGET_DIR/cursor-agent" ]] || [[ ! -L "$TARGET_DIR/agent" ]]; then
      echo "[FAIL] Case 1 (absent): symlinks not created" >&2
      exit 1
    fi
    echo "[PASS] Case 1 (absent): symlinks created"

    # Case 2: Regular file -> replaced with symlink
    rm -f "$TARGET_DIR/cursor-agent"
    echo "fake-file" > "$TARGET_DIR/cursor-agent"
    "$RECLAIM_SCRIPT" "$NIX_BINARY" "$TARGET_DIR"
    if [[ ! -L "$TARGET_DIR/cursor-agent" ]]; then
      echo "[FAIL] Case 2 (regular file): not replaced with symlink" >&2
      exit 1
    fi
    echo "[PASS] Case 2 (regular file): replaced with symlink"

    # Case 3: Symlink -> replaced (idempotent)
    "$RECLAIM_SCRIPT" "$NIX_BINARY" "$TARGET_DIR"
    if [[ ! -L "$TARGET_DIR/cursor-agent" ]]; then
      echo "[FAIL] Case 3 (symlink): not idempotent" >&2
      exit 1
    fi
    echo "[PASS] Case 3 (symlink): idempotent rerun"

    # Case 4: Real directory -> rejection (non-zero exit, directory preserved)
    rm -rf "$TARGET_DIR/cursor-agent"
    mkdir -p "$TARGET_DIR/cursor-agent"
    if "$RECLAIM_SCRIPT" "$NIX_BINARY" "$TARGET_DIR"; then
      echo "[FAIL] Case 4 (real directory): should have exited with error" >&2
      exit 1
    fi
    if [[ ! -d "$TARGET_DIR/cursor-agent" ]]; then
      echo "[FAIL] Case 4 (real directory): directory not preserved" >&2
      exit 1
    fi
    echo "[PASS] Case 4 (real directory): rejected, directory preserved"

    # Case 5: Wrong arity -> usage message + non-zero exit
    if "$RECLAIM_SCRIPT" "$NIX_BINARY"; then
      echo "[FAIL] Case 5 (wrong arity): should have exited with error" >&2
      exit 1
    fi
    echo "[PASS] Case 5 (wrong arity): rejected with usage message"

    # Cleanup
    rm -rf "$TMP_HOME"

    echo "[SANDBOX] All five cases passed"
    touch $out
  '';

  cursor-activation-regression = helpers.mkDefaultsRegression {
    label = "Cursor activation";
    checkName = "check-cursor-activation-regression";
    checks = [
      {
        name = "cursor.configMerge activation present";
        actual = hmConfig.config.home.activation ? cursorConfigMerge;
        expected = true;
      }
      {
        name = "cursorAgentReclaim activation present";
        actual = hmConfig.config.home.activation ? cursorAgentReclaim;
        expected = true;
      }
    ];
  };
}