# Vision-language backend routing regression (catalog -> modelBackends -> cmd).
#
# Split out of ./mlx-catalog.nix at the repo per-file size cap.
#
# WHAT THIS GUARDS: mlx_lm.server exposes no image input, so a vision-language
# model routed onto it does not fail loudly — it loads and then cannot answer.
# A silent fallback to the host backend is therefore invisible to any check
# that only asserts "a command was produced", which is why this asserts the
# selected BINARY and the absent flags rather than the command's existence.
#
# The backend stubs use DISTINCT names on purpose. Production names both the
# mlx-lm launcher and the mlx-vlm wrapper "mlx-model-server", so asserting
# against that shared name would pass even if per-model routing silently fell
# back to the host backend. Distinct stub names make the routing observable.
{
  pkgs,
  hmConfigCatalog,
  src,
}:
let
  c = hmConfigCatalog.config.programs.mlx;
  ocr = "mlx-community/Unlimited-OCR-bf16";
  commandBuilder = import ../../modules/mlx/model-server-cmd.nix {
    inherit (pkgs) lib;
    cfg = c;
    mlxModelServerPkg = pkgs.writeShellScriptBin "mlx-model-server" "";
    mlxModelServerPkgs = {
      mlx-vlm = pkgs.writeShellScriptBin "stub-mlx-vlm-server" "";
    };
  };
  ocrCmd = commandBuilder.mkModelCmd ocr;
  # mlx_vlm.server shares only --model/--port/--host with mlx_lm.server and
  # rejects the rest, so a leaked mlx-lm flag is a startup failure, not a
  # cosmetic difference.
  mustHave = [
    ".*stub-mlx-vlm-server --model ${ocr} .*"
    ".*--trust-remote-code.*"
  ];
  mustNotHave = [
    ".*--decode-concurrency.*"
    ".*--prompt-cache-bytes.*"
    ".*--harmony-tool-parser.*"
    ".*--max-num-seqs.*"
  ];
in
{
  mlx-catalog-vlm =
    assert
      builtins.all (m: builtins.match m ocrCmd != null) mustHave
      && builtins.all (m: builtins.match m ocrCmd == null) mustNotHave
      || throw "catalog: the OCR entry must compile onto mlx_vlm.server carrying no mlx_lm-only flags: ${ocrCmd}";
    # A per-model override that silently became a global one would move every
    # text model on the host onto a backend tuned for none of them.
    assert
      c.modelBackends.${ocr} == "mlx-vlm" && c.modelServerBackend == "mlx-lm"
      || throw "catalog: OCR must override its own backend only; the host backend must stay mlx-lm";
    # The serving host sets proxy.idleTtl = 0 and mlx_vlm.server has no
    # worker-side idle unload, so this per-entry TTL is the only path that ever
    # frees the weights. Absence leaks them until the proxy restarts.
    assert
      c.modelTtls.${ocr} == 600
      || throw "catalog: OCR must carry its per-entry 600s TTL — the only eviction path a VLM worker has";
    pkgs.runCommand "check-mlx-catalog-vlm" { } "touch $out";

  # Request-handling unit tests for the adapter the mlx-vlm backend runs. The
  # generation path needs a real model and is exercised by hand; these cover
  # the message/image parsing around it, including the refusal of image refs
  # that are not data: or http(s) URLs.
  #
  # `&&`, never `;`: with a semicolon touch $out runs even when the test exits
  # non-zero, so the derivation succeeds and the check can never fail.
  mlx-vlm-adapter = pkgs.runCommand "check-mlx-vlm-adapter" { } ''
    ${pkgs.python3}/bin/python3 ${src}/tests/test-mlx-vlm-adapter.py && touch $out
  '';
}
