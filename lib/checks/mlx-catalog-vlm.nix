# OCR backend and native mlx-vlm MTP command contracts.
{
  pkgs,
  src,
  hmConfigCatalog,
}:
let
  c = hmConfigCatalog.config.programs.mlx;
  mlxVlmInstallSpec = (import ../versions.nix).mlxVlmInstallSpec;
  ocr = "mlx-community/Unlimited-OCR-bf16";
  ocrBuilder = import ../../modules/mlx/model-server-cmd.nix {
    inherit (pkgs) lib;
    cfg = c;
    mlxModelServerPkg = pkgs.writeShellScriptBin "mlx-model-server" "";
    mlxModelServerPkgs = {
      mlx-vlm = pkgs.writeShellScriptBin "stub-mlx-vlm-server" "";
    };
  };
  ocrCmd = ocrBuilder.mkModelCmd ocr;
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
    cfg = mtpCfg;
    mlxModelServerPkg = pkgs.writeShellScriptBin "mlx-model-server" "";
    mlxModelServerPkgs = {
      mlx-vlm-native = pkgs.writeShellScriptBin "stub-mlx-vlm-native-server" "";
    };
  };
  command = commandBuilder.mkModelCmd mtpTarget;
  env =
    (import ../../modules/mlx/worker-env.nix {
      inherit (pkgs) lib;
      cfg = mtpCfg;
    }).workerEnv
      mtpTarget;
in
{
  mlx-catalog-vlm =
    assert
      builtins.match ".*stub-mlx-vlm-server --model ${ocr} .*" ocrCmd != null
      && builtins.match ".*--trust-remote-code.*" ocrCmd != null
      && builtins.match ".*--decode-concurrency.*" ocrCmd == null
      && builtins.match ".*--prompt-cache-bytes.*" ocrCmd == null
      || throw "catalog: OCR must compile onto the VLM adapter without mlx-lm-only flags: ${ocrCmd}";
    assert
      c.modelBackends.${ocr} == "mlx-vlm" && c.modelServerBackend == "mlx-lm"
      || throw "catalog: OCR must override only its own backend";
    pkgs.runCommand "check-mlx-catalog-vlm" { } "touch $out";

  mlx-vlm-install-spec =
    assert
      builtins.match "mlx-vlm @ https://github\\.com/Blaizzy/mlx-vlm/archive/[0-9a-f]{40}\\.zip" mlxVlmInstallSpec
      != null
      || throw "mlx-vlm install spec must resolve to a commit-pinned upstream archive: ${mlxVlmInstallSpec}";
    pkgs.runCommand "check-mlx-vlm-install-spec" { } "touch $out";

  mlx-vlm-adapter = pkgs.runCommand "check-mlx-vlm-adapter" { } ''
    ${pkgs.python3}/bin/python3 ${src}/tests/test-mlx-vlm-adapter.py && touch $out
  '';

  # Reachability is also covered through the module system by mlx-mtp-reachable.
  mlx-mtp-native-contract =
    assert
      builtins.match ".*stub-mlx-vlm-native-server --model ${mtpTarget} .*" command != null
      && builtins.match ".*--max-kv-size 131072.*" command != null
      && builtins.match ".*--draft-model ${mtpDrafter}.*" command != null
      && builtins.match ".*--draft-kind mtp.*" command != null
      && builtins.match ".*--draft-block-size 4.*" command != null
      && builtins.match ".*--max-num-seqs 1.*" command != null
      && env.MLX_VLM_TOKEN_QUEUE_TIMEOUT == "1800"
      || throw "catalog: enabled native MTP must emit its target, drafter, 128k window, batch width, and long-context queue timeout";
    pkgs.runCommand "check-mlx-mtp-native-contract" { } "touch $out";
}
