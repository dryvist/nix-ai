#
# MLX Module — CLI Tools, Environment & Ecosystem
#
# All home.packages and home.sessionVariables for the MLX module.
# Includes: official mlx_lm.server wrapper, MLX CLI tools, health check,
# and ecosystem uvx wrappers (parakeet-mlx, mlx-vlm).
#
# Orchestrated sweep runs live in the companion repo JacobPEvans/mlx-benchmarks;
# results are published to https://huggingface.co/datasets/JacobPEvans/mlx-benchmarks
#
{
  config,
  lib,
  pkgs,
  mlxShared,
  ...
}:
let
  inherit (mlxShared)
    cfg
    mlxModelServerPkg
    vllmMlxPkg
    mlxWarmupPkg
    mlxWatchdogPkg
    vllmMlxVersion
    parakeetMlxVersion
    mlxVlmVersion
    apiUrl
    uvPythonVersion
    launchAgentLabel
    warmupAgentLabel
    llamaSwapPkg
    llamaSwapConfigFile
    llamaSwapRuntimeConfigPath
    ;
  versions = import ../../lib/versions.nix;
  vllmMlxPin = "vllm-mlx==${vllmMlxVersion}";
  mlxLmVersion = versions.mlxLm;
  lmEvalVersion = versions.lmEval;
in
{
  config = lib.mkIf cfg.enable {
    home = {
      # ==========================================================================
      # Environment Variables
      # ==========================================================================
      sessionVariables = {
        MLX_API_URL = apiUrl;
        MLX_DEFAULT_MODEL = cfg.defaultModel;
        MLX_PRELOAD_MODELS = lib.concatStringsSep " " cfg.preload;
        MLX_PRELOAD_MODELS_JSON = builtins.toJSON cfg.preload;
        MLX_PORT = toString cfg.port;
        MLX_HOST = cfg.host;
        MLX_HF_HOME = cfg.huggingFaceHome;
        MLX_LAUNCHD_LABEL = launchAgentLabel;
        MLX_WARMUP_LABEL = warmupAgentLabel;
        MLX_MODEL_SERVER_PROCESS_PATTERN = mlxShared.modelServerProcessPattern;
        MLX_LLAMA_SWAP_CONFIG = llamaSwapRuntimeConfigPath;
        MLX_LLAMA_SWAP_BASE_CONFIG = "${llamaSwapConfigFile}";
      };

      # ==========================================================================
      # CLI Tools
      # ==========================================================================
      packages = [
        # Official Apple OpenAI-compatible model server.
        mlxModelServerPkg

        # mlx — one-shot prompt (curl + jq, no Python)
        (pkgs.writeShellApplication {
          name = "mlx";
          runtimeInputs = with pkgs; [
            curl
            jq
          ];
          text = builtins.readFile ./scripts/mlx.sh;
        })

        # mlx-switch — switch active model via llama-swap proxy
        (pkgs.writeShellApplication {
          name = "mlx-switch";
          runtimeInputs = with pkgs; [
            curl
            jq
          ];
          text = builtins.readFile ./scripts/mlx-switch.sh;
        })

        # mlx-default — restart llama-swap proxy (preloads default model)
        (pkgs.writeShellApplication {
          name = "mlx-default";
          runtimeInputs = [ ];
          text = builtins.readFile ./scripts/mlx-default.sh;
        })

        # mlx-warmup — fault the declared preload list into resident memory
        mlxWarmupPkg

        # llama-swap — proxy binary on PATH for direct invocation and mlx-default
        llamaSwapPkg

        # mlx-status — show running model, memory, uptime, LaunchAgent state
        (pkgs.writeShellApplication {
          name = "mlx-status";
          runtimeInputs = with pkgs; [
            curl
            jq
            lsof
            bc
          ];
          text = builtins.readFile ./scripts/mlx-status.sh;
        })

        # mlx-chat — interactive multi-turn chat via openai SDK
        (pkgs.writeShellScriptBin "mlx-chat" ''
          exec ${pkgs.uv}/bin/uv run \
            --python ${uvPythonVersion} \
            --with "openai==2.32.0" \
            python3 ${./scripts/mlx-chat.py} "$@"
        '')

        # ======================================================================
        # Pre-flight Memory Check
        # ======================================================================

        # mlx-preflight — validate model fits in memory before loading
        (pkgs.writeShellApplication {
          name = "mlx-preflight";
          runtimeInputs = with pkgs; [ coreutils ];
          text = builtins.readFile ./scripts/mlx-preflight.sh;
        })

        # ======================================================================
        # Benchmark Suite
        # ======================================================================

        # mlx-bench-raw — official MLX prefill + decode benchmark.
        # transformers pinned for the same mlx-lm import break as the server
        # wrapper (lib/versions.nix incident note).
        (pkgs.writeShellScriptBin "mlx-bench-raw" ''
          exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "mlx-lm==${mlxLmVersion}" --with "transformers==${versions.transformers}" mlx_lm.benchmark "$@"
        '')

        # mlx-eval — accuracy evaluation against the live mlx_lm.server API
        #
        # MLX_EVAL_CONCURRENT defaults to 1 because production serving is
        # intentionally serial while official mlx_lm concurrency is qualified.
        #
        # max_length=32768 is critical: lm-eval's local-chat-completions backend
        # defaults max_length to 2048, leaving only ~1023 tokens for the prompt
        # after max_gen_toks. Chat-wrapped HumanEval/MBPP prompts blow through
        # that instantly and responses get truncated mid-word (observed
        # 2026-04-10 with Qwen3-Coder-30B). 32k is a comfortable ceiling.
        #
        # The [api,math] extras bring in sympy + math_verify + antlr4 for
        # minerva_math500, which is the math-hard suite task currently run.
        #
        (pkgs.writeShellScriptBin "mlx-eval" ''
          concurrent="''${MLX_EVAL_CONCURRENT:-1}"
          exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "lm-eval[api,math]==${lmEvalVersion}" lm-eval run \
            --model local-chat-completions \
            --model_args "base_url=''${MLX_API_URL:-${apiUrl}}/chat/completions,model=''${MLX_DEFAULT_MODEL:-${cfg.defaultModel}},tokenizer_backend=None,tokenized_requests=False,num_concurrent=''${concurrent},max_retries=3,max_length=32768" \
            --apply_chat_template \
            "$@"
        '')

        # ======================================================================
        # Health Check
        # ======================================================================

        # mlx-wait — poll /v1/models until the server is ready (closes #254)
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
                echo "Timed out waiting for mlx_lm.server after ''${timeout}s" >&2
                exit 1
              fi
            done
            echo "mlx_lm.server ready (''${elapsed}s)"
          '';
        })

        # mlx-watchdog — one probe-and-maybe-kickstart cycle for the zombie
        # self-heal (also run every 60s by the mlx-lm watchdog LaunchAgent).
        # On PATH for manual break-fix / testing.
        mlxWatchdogPkg

        # ======================================================================
        # Model Inventory
        # ======================================================================

        # mlx-models — list all downloaded models with memory fit status
        (pkgs.writeShellApplication {
          name = "mlx-models";
          runtimeInputs = with pkgs; [
            coreutils
            curl
            jq
          ];
          text = builtins.readFile ./scripts/mlx-models.sh;
        })

        # mlx-discover — auto-discover downloaded models and register with llama-swap.
        # MLX_PRELOAD_MODELS_JSON is baked in (not taken from the shell) so the
        # wrapper works from any env, matching the activation hook.
        (pkgs.writeShellScriptBin "mlx-discover" ''
          export MLX_PRELOAD_MODELS_JSON=${lib.escapeShellArg (builtins.toJSON cfg.preload)}
          exec ${pkgs.python3}/bin/python3 "${./discover-models.py}" "$@"
        '')

        # ======================================================================
        # MLX Ecosystem — Ears & Eyes
        # ======================================================================

        # parakeet-mlx — real-time speech-to-text transcription
        (pkgs.writeShellApplication {
          name = "parakeet-mlx";
          runtimeInputs = [ pkgs.ffmpeg ]; # librosa needs ffmpeg for audio decoding
          text = ''
            exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "parakeet-mlx==${parakeetMlxVersion}" parakeet-mlx "$@"
          '';
        })

        # mlx-vlm-generate — vision language model image analysis
        (pkgs.writeShellScriptBin "mlx-vlm-generate" ''
          exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "mlx-vlm==${mlxVlmVersion}" mlx_vlm.generate "$@"
        '')
      ]
      ++ lib.optionals (lib.elem "vllm-mlx" cfg.enabledBackends) [
        # Preserved for future requalification; absent from deployed hosts while
        # the backend is disabled.
        vllmMlxPkg
        (pkgs.writeShellScriptBin "mlx-bench" ''
          exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "${vllmMlxPin}" vllm-mlx-bench "$@"
        '')
        (pkgs.writeShellScriptBin "mlx-bench-engine" ''
          exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "${vllmMlxPin}" vllm-mlx bench "$@"
        '')
      ];
    };
  };
}
