# shellcheck shell=bash
# The harmony patch is only useful if it lands in the mlx-lm the worker runs.
#
# Applying the patch is what builds $mlxLmRoot's derivation, so an upstream bump
# that moves an anchor fails while building this check rather than at model-load
# time. The greps then pin what the patch must have produced.
#
# The last two are the ones #1429 needed and did not have. That defect was never
# in the parser — it was the UNGATED ternary handing ToolCallFormatter the
# harmony parser on every model, including one whose template correctly inferred
# qwen3_coder. The check stayed green throughout, because it only ever asked
# whether harmony was PRESENT. So: the gated helper must be present, and the
# ungated ternary must be absent.
#
# Was harmony-wheel-test.sh, unzipping a patched wheel. mlx-lm is now a source
# derivation (modules/mlx/python-overlay.nix), so the patched files are read
# directly — same assertions, one less layer.
#
# Every step chains with `&&` and $out is touched only on success; a `;` anywhere
# here would make this check structurally unable to fail.
#
# Usage: mlxLmRoot=/nix/store/...-env/lib/pythonX.Y/site-packages \
#        out=/tmp/x bash harmony-patch-test.sh

set -o errexit
set -o nounset
set -o pipefail

# Supplied by the derivation environment. Bound here with :? so an unset one
# names itself instead of surfacing as a file-not-found further down.
mlxLmRoot="${mlxLmRoot:?site-packages dir of the built patched mlx-lm}"
out="${out:?derivation output path}"

server="$mlxLmRoot/mlx_lm/server.py"

test -f "$mlxLmRoot/mlx_lm/tool_parsers/harmony.py" \
  && grep -- '--harmony-tool-parser' "$server" >/dev/null \
  && grep '_make_harmony_stream' "$server" >/dev/null \
  && grep '_select_tool_parser(harmony_stream, ctx)' "$server" >/dev/null \
  && ! grep -q '_harmony_parse_tool_call if harmony_stream is not None else ctx.tool_parser,' "$server" \
  && touch "$out"
