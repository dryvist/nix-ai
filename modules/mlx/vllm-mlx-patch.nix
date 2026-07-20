# Patched vllm-mlx wheel — split from default.nix (file-size gate).
#
# vllm-mlx 0.4.0 hardcodes its logging level with no CLI flag or env var:
#   server.py:  logging.basicConfig(level=logging.INFO)
#   cli.py:     uvicorn.run(app, host=args.host, port=args.port, log_level="info")
# (confirmed via `vllm-mlx serve --help` and a source read of both files —
# no --log-level flag exists anywhere in the argparse tree). This derivation
# patches only those two call sites to read VLLM_MLX_LOG_LEVEL (falling back
# to the same upstream defaults), so programs.mlx.serverLogLevel
# (options-runtime.nix) controls the app logger AND uvicorn's own request
# logging. No other behavior changes.
#
# Patches the prebuilt wheel, not the sdist: pointing uvx's `--from` at a
# source directory made uv try to build it in place via setuptools, which
# fails against a read-only Nix store path ("Cannot update time stamp of
# directory 'vllm_mlx.egg-info'"). A wheel is just a zip; unzip, patch the
# two .py files, rezip — no build step, so the read-only store path is never
# written to by the consumer.
{ pkgs, vllmMlxVersion }:
let
  wheelSrc = pkgs.fetchurl {
    url = "https://files.pythonhosted.org/packages/bf/4e/1fb1768a77caeae55376d6e2f3cc053da9809bc6b19567473977ff74c132/vllm_mlx-${vllmMlxVersion}-py3-none-any.whl";
    hash = "sha256-qSUwLyHeC688OoMlDDZGlWOKqmMf+9wuWBtpSISMZbo=";
  };
  wheelName = "vllm_mlx-${vllmMlxVersion}-py3-none-any.whl";
in
pkgs.runCommand "vllm-mlx-wheel-patched-${vllmMlxVersion}"
  {
    nativeBuildInputs = [
      pkgs.unzip
      pkgs.zip
    ];
  }
  ''
    mkdir -p unpacked
    unzip -q ${wheelSrc} -d unpacked

    # server.py already imports os; only the hardcoded level needs to move.
    substituteInPlace unpacked/vllm_mlx/server.py \
      --replace-fail \
        'logging.basicConfig(level=logging.INFO)' \
        'logging.basicConfig(level=os.environ.get("VLLM_MLX_LOG_LEVEL", "INFO").upper())'

    # cli.py has no module-level `os` import; add one, then read the same var
    # for uvicorn's own log_level (which takes lowercase names and has no
    # "warn" alias the way Python's logging module does, hence the map).
    # Anchored on the two-line "import json\nimport sys" span (the bare
    # top-level `import sys` string alone also matches an unrelated indented
    # local import inside a function later in the file) and built via printf
    # (not a literal multi-line Nix string) so the injected Python's
    # indentation is exact, independent of this file's own formatting.
    substituteInPlace unpacked/vllm_mlx/cli.py \
      --replace-fail \
        "$(printf 'import json\nimport sys')" \
        "$(printf 'import json\nimport sys\nimport os')" \
      --replace-fail \
        'uvicorn.run(app, host=args.host, port=args.port, log_level="info")' \
        "$(printf '_vllm_mlx_log_level = os.environ.get("VLLM_MLX_LOG_LEVEL", "info").lower()\n    _vllm_mlx_log_level = {"warn": "warning"}.get(_vllm_mlx_log_level, _vllm_mlx_log_level)\n    uvicorn.run(app, host=args.host, port=args.port, log_level=_vllm_mlx_log_level)')"

    # _build_engine is the lifecycle/residency construction path, taken
    # whenever --auto-unload-idle-seconds or --lazy-load-model is set. Unlike
    # the direct load path (server.py, which passes
    # gpu_memory_utilization=gpu_memory_utilization), it omits the argument
    # entirely, so BatchedEngine falls back to its 0.90 default and the CLI
    # flag is silently discarded.
    #
    # That value is not cosmetic: BatchedEngine feeds it into EngineConfig,
    # from which engine_core derives the emergency KV-clear trip point at
    # device_mem * (util + 0.05). Stuck at 0.90, the trip lands at ~130 GB —
    # above any wired ceiling a 128 GB host can have — so the soft valve never
    # fires and the OS ceiling becomes the only bound.
    #
    # ModelSpec carries no utilization field, so threading it through the
    # dataclass would be a larger upstream change. Read the env instead,
    # keeping the same 0.90 fallback, mirroring VLLM_MLX_LOG_LEVEL above.
    # server.py already imports os.
    substituteInPlace unpacked/vllm_mlx/server.py \
      --replace-fail \
        "$(printf 'return BatchedEngine(\n            model_name=spec.model_name,\n            scheduler_config=spec.scheduler_config,\n            stream_interval=spec.stream_interval,\n            force_mllm=spec.force_mllm,\n        )')" \
        "$(printf 'return BatchedEngine(\n            model_name=spec.model_name,\n            scheduler_config=spec.scheduler_config,\n            stream_interval=spec.stream_interval,\n            force_mllm=spec.force_mllm,\n            gpu_memory_utilization=float(\n                os.environ.get("VLLM_MLX_GPU_MEMORY_UTILIZATION", "0.90")\n            ),\n        )')"

    mkdir -p $out
    (cd unpacked && zip -qr "$out/${wheelName}" .)
  ''
