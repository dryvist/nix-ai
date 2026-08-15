# The harmony (gpt-oss) tool-call patch for mlx-lm: one definition, two consumers.
#
# THE DEFECT
#
# mlx-lm 0.31.3 (upstream's newest release — the pin is current, not stale)
# infers a tool parser from the chat template in
# tokenizer_utils._infer_tool_parser. None of its branches match gpt-oss, so
# `has_tool_calling` is False and the model's own, semantically correct harmony
# tool call —
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
# `auto` gates PARSER SELECTION, not only content. The first cut gated the
# content path alone, so `auto` still handed ToolCallFormatter the harmony
# parser on every model — including Qwen3.6-35B-A3B-4bit, whose template
# correctly infers qwen3_coder. Each well-formed Qwen tool call raised inside
# the formatter, got swallowed to `[]`, and the response omitted `tool_calls`
# entirely though `finish_reason` already said "tool_calls": a turn carrying
# neither calls nor content. `_make_harmony_stream` now engages in `auto` only
# on a model that inferred no parser of its own. See mlx-lm-patch/test_selection.py.
#
# Staying on the 0.31.3 RELEASE is deliberate: catalog-lib.nix documents that
# the only route past it is a git-wheel serverVariant which DROPS
# --harmony-tool-parser, the very flag gpt-oss needs. Release-plus-patch is the
# only viable route — do not drift toward the git wheel.
#
# WHY TWO EXPORTS
#
# This used to unzip the PyPI wheel, patch it, and rezip. mlx-lm now comes from
# a nixpkgs source derivation (modules/mlx/python-overlay.nix), so applying the
# patch is an ordinary postPatch — smaller, and it keeps nixpkgs' check phase.
#
# But the regression checks run on x86_64-linux (see flake.nix `checks`) while
# the runtime package is darwin-only: mlx's Metal wheel is aarch64-darwin, so
# the built package cannot exist on the CI system. The checks do not need it —
# wheel_under_test.py lifts each definition out with `ast` precisely BECAUSE
# mlx_lm.server imports mlx and transformers at package level and neither
# exists off Apple silicon. They need the patched SOURCE, nothing more.
#
# So: `postPatch` is the shared patch step, and `patchedSrc` is a
# platform-independent tree with that same step applied. Both apply the
# identical two commands, so the checks cannot drift from what ships.
{ pkgs }:
rec {
  # The patch step, shared verbatim by the runtime override and patchedSrc.
  # Run from the mlx-lm source root (the dir containing mlx_lm/).
  postPatch = ''
    cp ${./mlx-lm-patch/harmony.py} mlx_lm/tool_parsers/harmony.py
    patch -p1 < ${./mlx-lm-patch/server-harmony.patch}
  '';

  # Patched mlx-lm source, buildable on any platform. For the regression checks
  # only — the runtime package applies `postPatch` above inside its own build.
  # Byte-identical .py files either way, so a green check here is a real
  # statement about what the worker runs.
  patchedSrc =
    pkgs.runCommand "mlx-lm-src-harmony-${pkgs.python3Packages.mlx-lm.version}"
      {
        src = pkgs.python3Packages.mlx-lm.src;
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        cp -r "$src" build && chmod -R u+w build && cd build
        ${postPatch}

        # Fail loudly here rather than at model-load time.
        python3 -m py_compile mlx_lm/server.py mlx_lm/tool_parsers/harmony.py

        mkdir -p "$out" && cp -r mlx_lm "$out/"
      '';
}
