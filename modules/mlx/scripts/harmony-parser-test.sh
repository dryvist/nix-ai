# shellcheck shell=bash
# Harmony/tool-parser unit tests, run against the PATCHED WHEEL.
#
# test_selection.py lifts its subjects (_make_harmony_stream, _select_tool_parser,
# ToolCallFormatter, _LoudToolCallFormatter, _infer_tool_parser, parse_tool_call)
# straight out of the wheel named by $MLX_LM_ROOT rather than re-stating them, so
# an upstream rename fails extraction loudly instead of quietly testing nothing.
# It REFUSES to run when $MLX_LM_ROOT is unset — hence the unpack below.
#
# Pointing MLX_LM_ROOT at the patch source instead of the built wheel would still
# pass while covering the copy rather than the server.py that actually ships.
#
# Every step chains with `&&` and $out is touched only on success; a `;` anywhere
# here would make this check structurally unable to fail.
#
# Usage: wheel=/path/to.whl patchSrc=/path/to/mlx-lm-patch python3=/path/to/python3 \
#        out=/tmp/x NIX_BUILD_TOP=/tmp bash harmony-parser-test.sh

set -o errexit
set -o nounset
set -o pipefail

# Supplied by the derivation environment. Bound here with :? so an unset one
# names itself instead of surfacing as an unzip/exec error further down.
wheel="${wheel:?path to the built patched mlx-lm wheel}"
patchSrc="${patchSrc:?path to modules/mlx/mlx-lm-patch}"
python3="${python3:?path to a python3 that has the regex module}"
out="${out:?derivation output path}"
buildTop="${NIX_BUILD_TOP:?build directory holding the unpacked wheel}"

unzip -q "$wheel" -d ./wheel \
  && cp -r "$patchSrc" ./patch \
  && chmod -R u+w ./patch \
  && cd ./patch \
  && MLX_LM_ROOT="$buildTop/wheel" "$python3" -m unittest discover -v -p 'test_*.py' \
  && touch "$out"
