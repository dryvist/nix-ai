# shellcheck shell=bash
# The harmony patch is only useful if it lands in the wheel the worker runs.
#
# Applying the patch is what builds $wheel, so an upstream bump that moves an
# anchor fails while building this check rather than at model-load time. The
# greps then pin what the patch must have produced.
#
# The last two are the ones #1429 needed and did not have. That defect was never
# in the parser — it was the UNGATED ternary handing ToolCallFormatter the
# harmony parser on every model, including one whose template correctly inferred
# qwen3_coder. The wheel check stayed green throughout, because it only ever
# asked whether harmony was PRESENT. So: the gated helper must be present, and
# the ungated ternary must be absent.
#
# Every step chains with `&&` and $out is touched only on success; a `;` anywhere
# here would make this check structurally unable to fail.
#
# Usage: wheel=/path/to.whl out=/tmp/x bash harmony-wheel-test.sh

set -o errexit
set -o nounset
set -o pipefail

# Supplied by the derivation environment. Bound here with :? so an unset one
# names itself instead of surfacing as an unzip error further down.
wheel="${wheel:?path to the built patched mlx-lm wheel}"
out="${out:?derivation output path}"

unzip -l "$wheel" | grep 'mlx_lm/tool_parsers/harmony.py' >/dev/null \
  && unzip -p "$wheel" mlx_lm/server.py | grep -- '--harmony-tool-parser' >/dev/null \
  && unzip -p "$wheel" mlx_lm/server.py | grep '_make_harmony_stream' >/dev/null \
  && unzip -p "$wheel" mlx_lm/server.py \
    | grep '_select_tool_parser(harmony_stream, ctx)' >/dev/null \
  && ! unzip -p "$wheel" mlx_lm/server.py \
    | grep -q '_harmony_parse_tool_call if harmony_stream is not None else ctx.tool_parser,' \
  && touch "$out"
