# Harmony (gpt-oss) tool-call parser regression tests.
#
# Three independent layers, because each can break without the others noticing:
#   1. the parser itself, against verbatim gpt-oss-120b responses;
#   2. the wheel patch actually applying to the pinned mlx-lm;
#   3. the nix flag reaching the deployed serve command, per model.
#
# Every derivation chains with `&&` and touches $out only on success — a `;`
# here would make the check structurally unable to fail.
{ pkgs, hmConfigCatalog }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  patchSrc = ../../modules/mlx/mlx-lm-patch;
  pythonTests = ../../tests/mlx-lm-patch;
  # The patched mlx-lm source. Was an unzipped wheel; mlx-lm now carries the
  # harmony patch as a postPatch (modules/mlx/python-overlay.nix), and
  # mlx-lm-patch.nix exports that same step applied to a platform-independent
  # tree. These checks run on x86_64-linux while the runtime package is
  # darwin-only (Metal wheel), and they lift definitions with `ast` rather than
  # importing, so the source tree is exactly what they need.
  mlxLmRoot = (import ../../modules/mlx/mlx-lm-patch.nix { inherit pkgs; }).patchedSrc;

  c = hmConfigCatalog.config.programs.mlx;
  gptOss = "mlx-community/gpt-oss-120b-MXFP4-Q8";
  commandBuilder = import ../../modules/mlx/model-server-cmd.nix {
    inherit (pkgs) lib;
    cfg = c;
    mlxModelServerPkg = pkgs.writeShellScriptBin "mlx-model-server" "";
  };
  gptOssCmd = commandBuilder.mkModelCmd gptOss;
  uncataloguedCmd = commandBuilder.mkModelCmd "mlx-community/test-model";
  has = needle: haystack: builtins.match ".*${needle}.*" haystack != null;
in
{
  # Unit tests for modules/mlx/mlx-lm-patch/harmony.py. Fixtures are verbatim
  # gpt-oss-120b-MXFP4-Q8 responses captured 2026-07-27 from an isolated,
  # ps-proven worker — the exact payloads that shipped `tool_calls: null`.
  #
  # Runs against the BUILT PACKAGE, not the patch source: test_selection.py lifts
  # its subjects out of $MLX_LM_ROOT and refuses to run without it, so that an
  # upstream rename breaks extraction loudly instead of testing a stale copy.
  mlx-harmony-parser = pkgs.runCommand "check-mlx-harmony-parser" {
    inherit mlxLmRoot patchSrc pythonTests;
    # `regex`, because the wheel's own tool_parsers/qwen3_coder.py imports it —
    # a bare python3 stops at that import and never reaches the assertions.
    python3 = "${pkgs.python3.withPackages (ps: [ ps.regex ])}/bin/python3";
  } (builtins.readFile ../../tests/harmony-parser-test.sh);

  # The patch is only useful if it lands in the mlx-lm the worker actually runs.
  # Building this check applies it against the pinned mlx-lm release, so an
  # upstream bump that moves an anchor fails here instead of at model-load time.
  # It also pins the SELECTION gate, which is what #1429 shipped without: asking
  # only whether harmony is present kept this green while harmony was replacing
  # every other model's parser. See tests/harmony-patch-test.sh.
  mlx-harmony-patch = pkgs.runCommand "check-mlx-harmony-patch" {
    inherit mlxLmRoot;
  } (builtins.readFile ../../tests/harmony-patch-test.sh);

  # The flag must reach the serve command, and the catalog's per-model pin must
  # beat the global default — per-model divergence is the point here.
  mlx-harmony-flags =
    assert
      c.harmonyToolParser == "auto"
      || throw "mlx: harmonyToolParser default must stay \"auto\" (inert for non-harmony models), got ${c.harmonyToolParser}";
    assert
      c.modelFlagOverrides.${gptOss}.harmonyToolParser == "on"
      || throw "mlx: the gpt-oss catalog entry must pin harmonyToolParser = \"on\"";
    assert
      has "--harmony-tool-parser on" gptOssCmd
      || throw "mlx: gpt-oss serve command missing --harmony-tool-parser on: ${gptOssCmd}";
    assert
      has "--harmony-tool-parser auto" uncataloguedCmd
      || throw "mlx: uncatalogued model must inherit --harmony-tool-parser auto: ${uncataloguedCmd}";
    helpers.mkMarker "check-mlx-harmony-flags" "MLX harmony: --harmony-tool-parser compiled (gpt-oss=on, default=auto)";
}
