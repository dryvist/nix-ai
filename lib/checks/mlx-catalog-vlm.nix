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
  mtpTarget = "mlx-community/test-mtp-target";
  mtpDrafter = "mlx-community/test-mtp-drafter";
  mtpCfg = c // {
    modelBackends = c.modelBackends // {
      ${mtpTarget} = "mlx-vlm-native";
    };
    modelConcurrencyLimits = c.modelConcurrencyLimits // {
      ${mtpTarget} = 1;
    };
    modelMtpProfiles = c.modelMtpProfiles // {
      ${mtpTarget} = {
        enable = true;
        drafterModel = mtpDrafter;
        maxKvTokens = 131072;
        maxNumSeqs = 1;
        tokenQueueTimeoutSeconds = 1800;
        draftBlockSize = 4;
      };
    };
  };
  commandBuilder = import ../../modules/mlx/model-server-cmd.nix {
    inherit (pkgs) lib;
    cfg = c;
    mlxModelServerPkg = pkgs.writeShellScriptBin "mlx-model-server" "";
    mlxModelServerPkgs = {
      mlx-vlm = pkgs.writeShellScriptBin "stub-mlx-vlm-server" "";
    };
  };
  ocrCmd = commandBuilder.mkModelCmd ocr;
  mtpCommandBuilder = import ../../modules/mlx/model-server-cmd.nix {
    inherit (pkgs) lib;
    cfg = mtpCfg;
    mlxModelServerPkg = pkgs.writeShellScriptBin "mlx-model-server" "";
    mlxModelServerPkgs = {
      mlx-vlm-native = pkgs.writeShellScriptBin "stub-mlx-vlm-native-server" "";
    };
  };
  mtpCmd = mtpCommandBuilder.mkModelCmd mtpTarget;
  mtpEnv =
    (import ../../modules/mlx/worker-env.nix {
      inherit (pkgs) lib;
      cfg = mtpCfg;
    }).workerEnv
      mtpTarget;
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

  mlx-mtp-native-contract =
    assert
      builtins.match ".*stub-mlx-vlm-native-server --model ${mtpTarget} .*" mtpCmd != null
      && builtins.match ".*--max-kv-size 131072.*" mtpCmd != null
      && builtins.match ".*--draft-model ${mtpDrafter}.*" mtpCmd != null
      && builtins.match ".*--draft-kind mtp.*" mtpCmd != null
      && builtins.match ".*--draft-block-size 4.*" mtpCmd != null
      && builtins.match ".*--max-num-seqs 1.*" mtpCmd != null
      && builtins.elem "MLX_VLM_TOKEN_QUEUE_TIMEOUT=1800" mtpEnv
      || throw "catalog: enabled native MTP must emit its target, drafter, 128k window, batch width, and long-context queue timeout";
    pkgs.runCommand "check-mlx-mtp-native-contract" { } "touch $out";
}
