# MLX module CLI tools and ecosystem wrappers.
{
  lib,
  pkgs,
  mlxShared,
  ...
}:
let
  inherit (mlxShared)
    cfg
    mlxModelServerPkg
    parakeetMlxVersion
    mlxVlmVersion
    apiUrl
    uvPythonVersion
    ;
  versions = import ../../lib/versions.nix;
  mlxLmVersion = versions.mlxLm;
  lmEvalVersion = versions.lmEval;
in
{
  config = lib.mkIf cfg.enable {
    home = {
      sessionVariables = {
        MLX_API_URL = apiUrl;
        MLX_DEFAULT_MODEL = cfg.defaultModel;
        MLX_PORT = toString cfg.port;
        MLX_HOST = cfg.host;
        MLX_HF_HOME = cfg.huggingFaceHome;
      };

      packages = [
        mlxModelServerPkg

        (pkgs.writeShellApplication {
          name = "mlx";
          runtimeInputs = with pkgs; [
            curl
            jq
          ];
          text = builtins.readFile ./scripts/mlx.sh;
        })

        (pkgs.writeShellApplication {
          name = "mlx-preflight";
          runtimeInputs = with pkgs; [ coreutils ];
          text = builtins.readFile ./scripts/mlx-preflight.sh;
        })

        (pkgs.writeShellScriptBin "mlx-bench-raw" ''
          exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "mlx-lm==${mlxLmVersion}" --with "transformers==${versions.transformers}" mlx_lm.benchmark "$@"
        '')

        (pkgs.writeShellScriptBin "mlx-eval" ''
          concurrent="''${MLX_EVAL_CONCURRENT:-1}"
          exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "lm-eval[api,math]==${lmEvalVersion}" lm-eval run \
            --model local-chat-completions \
            --model_args "base_url=''${MLX_API_URL:-${apiUrl}}/chat/completions,model=''${MLX_DEFAULT_MODEL:-${cfg.defaultModel}},tokenizer_backend=None,tokenized_requests=False,num_concurrent=''${concurrent},max_retries=3,max_length=32768" \
            --apply_chat_template \
            "$@"
        '')

        (pkgs.writeShellApplication {
          name = "mlx-wait";
          runtimeInputs = with pkgs; [ curl ];
          text = ''
            timeout=''${1:-120}
            elapsed=0
            while ! curl -sf "${apiUrl}/models" > /dev/null; do
              sleep 2
              elapsed=$((elapsed + 2))
              if [ "$elapsed" -ge "$timeout" ]; then
                echo "Timed out waiting for the MLX server after ''${timeout}s" >&2
                exit 1
              fi
            done
            echo "MLX server ready (''${elapsed}s)"
          '';
        })

        (pkgs.writeShellApplication {
          name = "parakeet-mlx";
          runtimeInputs = [ pkgs.ffmpeg ];
          text = ''
            exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "parakeet-mlx==${parakeetMlxVersion}" parakeet-mlx "$@"
          '';
        })

        (pkgs.writeShellScriptBin "mlx-vlm-generate" ''
          exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "mlx-vlm==${mlxVlmVersion}" mlx_vlm.generate "$@"
        '')
      ];
    };
  };
}
