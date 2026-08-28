# shellcheck shell=bash
# Harmony/tool-parser unit tests, run against the BUILT mlx-lm PACKAGE.
#
# test_selection.py lifts its subjects (_make_harmony_stream, _select_tool_parser,
# ToolCallFormatter, _LoudToolCallFormatter, _infer_tool_parser, parse_tool_call)
# straight out of the tree named by $MLX_LM_ROOT rather than re-stating them, so
# an upstream rename fails extraction loudly instead of quietly testing nothing.
# It REFUSES to run when $MLX_LM_ROOT is unset.
#
# Pointing MLX_LM_ROOT at the patch source instead of the built package would
# still pass while covering the copy rather than the server.py that ships.
#
# Previously this unzipped a patched wheel. mlx-lm is now a source derivation
# (see modules/mlx/python-overlay.nix), so the patched tree is already on disk
# and there is nothing to unpack — $mlxLmRoot points straight at the
# site-packages the worker imports.
#
# Every step chains with `&&` and $out is touched only on success; a `;` anywhere
# here would make this check structurally unable to fail.
#
# Usage: mlxLmRoot=/nix/store/...-env/lib/pythonX.Y/site-packages \
#        patchSrc=/path/to/mlx-lm-patch python3=/path/to/python3 \
#        out=/tmp/x bash harmony-parser-test.sh

set -o errexit
set -o nounset
set -o pipefail

# Supplied by the derivation environment. Bound here with :? so an unset one
# names itself instead of surfacing as an exec error further down.
mlxLmRoot="${mlxLmRoot:?site-packages dir of the built patched mlx-lm}"
patchSrc="${patchSrc:?path to modules/mlx/mlx-lm-patch}"
# The tests live in tests/mlx-lm-patch and `import harmony` from the patch
# source, so the patch dir goes on PYTHONPATH rather than holding the tests.
pythonTests="${pythonTests:?path to tests/mlx-lm-patch}"
python3="${python3:?path to a python3 that has the regex module}"
out="${out:?derivation output path}"

# Fail here rather than letting the tests "pass" against a tree with no mlx_lm.
test -f "$mlxLmRoot/mlx_lm/server.py" \
  && test -f "$mlxLmRoot/mlx_lm/tool_parsers/harmony.py" \
  && cp -r "$patchSrc" ./patch \
  && cp -r "$pythonTests" ./pytests \
  && chmod -R u+w ./patch ./pytests \
  && cd ./pytests \
  && MLX_LM_ROOT="$mlxLmRoot" PYTHONPATH="../patch:${PYTHONPATH:-}" \
    "$python3" -m unittest discover -v -p 'test_*.py' \
  && touch "$out"
