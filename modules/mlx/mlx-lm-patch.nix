# Patched mlx-lm wheel — harmony (gpt-oss) tool-call parsing.
#
# mlx-lm 0.31.3 (latest on PyPI as of 2026-07-27; upstream has NOT added a
# harmony parser) infers a tool parser from the chat template in
# tokenizer_utils._infer_tool_parser. None of its branches match gpt-oss, so
# `has_tool_calling` is False and the model's own, semantically correct
# harmony tool call —
#   <|channel|>commentary to=functions.NAME <|constrain|>json<|message|>{...}
# — is handed back verbatim inside `content` with `tool_calls: null` and
# `finish_reason: "stop"`. Every OpenAI-compatible client therefore sees zero
# tool calls, and the analysis channel leaks into ordinary completions too.
#
# The token-sequence state machine upstream uses for other parsers cannot bound
# a harmony tool call: its header is variable text (`to=functions.<name>`), not
# a fixed token run. So this adds mlx_lm/tool_parsers/harmony.py — an
# incremental segmenter for the channel grammar — and patches server.py to run
# it over the `normal` text stream in both the streaming and non-streaming
# paths. See mlx-lm-patch/harmony.py for the grammar and degradation contract.
#
# Patches the prebuilt wheel, not the sdist: a wheel is a zip, so unzip/patch/
# rezip needs no build step and never writes to a read-only store path. Same
# reasoning as vllm-mlx-patch.nix, which patches its wheel the same way.
#
# Returns the patched wheel's absolute path — a drop-in replacement for the
# `mlx-lm==<version>` pin wherever the serving stack resolves mlx-lm.
{ pkgs, mlxLmVersion }:
let
  wheelName = "mlx_lm-${mlxLmVersion}-py3-none-any.whl";
  wheelSrc = pkgs.fetchurl {
    url = "https://files.pythonhosted.org/packages/90/02/9a67b8e4f87e3e2e5cd7b1ad79304b93c09a0db6af34bee75e6551c06c60/${wheelName}";
    hash = "sha256-dYz93xGABTt2E9t2+tPSRqMxoqkFgI4RZKJ1Yh/Jg7g=";
  };
  patchedWheel =
    pkgs.runCommand "mlx-lm-wheel-harmony-${mlxLmVersion}"
      {
        nativeBuildInputs = [
          pkgs.unzip
          pkgs.zip
        ];
      }
      ''
        mkdir -p unpacked
        unzip -q ${wheelSrc} -d unpacked

        cp ${./mlx-lm-patch/harmony.py} unpacked/mlx_lm/tool_parsers/harmony.py
        chmod u+w unpacked/mlx_lm/server.py
        patch -p1 -d unpacked < ${./mlx-lm-patch/server-harmony.patch}

        # RECORD lists every installed file. Installers do not verify the
        # digests, but an unlisted file can be skipped by a strict unpacker —
        # declare it with the "unhashed" form the spec allows.
        echo 'mlx_lm/tool_parsers/harmony.py,,' \
          >> unpacked/mlx_lm-${mlxLmVersion}.dist-info/RECORD

        # Fail loudly here rather than at model-load time.
        ${pkgs.python3}/bin/python3 -m py_compile \
          unpacked/mlx_lm/server.py unpacked/mlx_lm/tool_parsers/harmony.py

        mkdir -p $out
        (cd unpacked && zip -qr "$out/${wheelName}" .)
      '';
in
"${patchedWheel}/${wheelName}"
