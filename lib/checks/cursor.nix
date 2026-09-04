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

  # Assert the reclaim activation data references the store binary, the
  # obsolete home.file symlinks are gone, and mcp.json + cursorConfigMerge
  # are conserved.
  cursor-reclaim-data = helpers.mkDefaultsRegression {
    label = "Cursor reclaim data";
    checkName = "check-cursor-reclaim-data";
    checks =
      let
        reclaimData = hmConfig.config.home.activation.cursorAgentReclaim.data or "";
        # Match the store path pattern: /nix/store/<hash>-cursor-cli-<version>/bin/cursor-agent
        # Avoid interpolating the derivation directly (Nix forbids store path refs in asserts).
        # builtins.match anchors to the WHOLE string, and the activation data is a
        # multi-line script, so the pattern must be wrapped to match a substring.
        # `(.|\n)*` rather than `.*` because `.` does not match a newline here.
        storePathPattern = "(.|\n)*/nix/store/[a-z0-9]+-cursor-cli-[^/]+/bin/cursor-agent(.|\n)*";
        hasStorePath = builtins.match storePathPattern reclaimData != null;
        homeFileNames = builtins.attrNames hmConfig.config.home.file;
        hasAgentLink = builtins.elem ".local/bin/agent" homeFileNames;
        hasCursorAgentLink = builtins.elem ".local/bin/cursor-agent" homeFileNames;
        hasMcpJson = builtins.elem ".cursor/mcp.json" homeFileNames;
        hasConfigMerge = hmConfig.config.home.activation ? cursorConfigMerge;
      in
      [
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
  cursor-reclaim-sandbox =
    pkgs.runCommand "check-cursor-reclaim-sandbox"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.bash
        ];
      }
      ''
        set -euo pipefail

        RECLAIM_SCRIPT="${../../modules/scripts/cursor-reclaim-links.sh}"
        NIX_BINARY="${pkgs.cursor-cli}/bin/cursor-agent"

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
