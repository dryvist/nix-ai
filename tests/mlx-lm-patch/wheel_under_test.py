# Copyright © 2026 JacobPEvans. Harness shared by the test_*.py in this dir.
"""Load the real patched wheel so the tests exercise it, not a restatement.

`mlx_lm.server` and `mlx_lm.tokenizer_utils` import mlx and transformers at
package level, neither of which exists off Apple silicon, so nothing here can be
imported normally. Instead each definition under test is lifted out of the real
source with `ast` and executed on its own. A rename or deletion upstream fails
the extraction loudly rather than quietly testing nothing.

$MLX_LM_ROOT is an unpacked *patched* wheel. Its absence is an error, never a
skip: a check that silently verifies nothing is worse than no check.
"""

import ast
import importlib.util
import json
import logging
import os
import uuid
from pathlib import Path

import harmony

FIXTURE = json.loads((Path(__file__).parent / "fixtures/qwen-non-harmony.json").read_text())

_ROOT_ENV = os.environ.get("MLX_LM_ROOT")
if not _ROOT_ENV:
    raise RuntimeError(
        "MLX_LM_ROOT must point at an unpacked patched mlx-lm wheel; these tests "
        "verify the real server.py selection code, not a copy of it."
    )
ROOT = Path(_ROOT_ENV)


def lift(relpath, names, extra_globals=None):
    """Execute just `names` from a source file, without importing its package."""
    path = ROOT / relpath
    tree = ast.parse(path.read_text(), filename=str(path))
    wanted = [
        node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in names
    ]
    missing = set(names) - {node.name for node in wanted}
    if missing:
        raise AssertionError(f"{relpath} no longer defines {sorted(missing)}")
    namespace = {"json": json, "logging": logging, "uuid": uuid}
    namespace.update(extra_globals or {})
    module = ast.Module(body=wanted, type_ignores=[])
    exec(compile(ast.fix_missing_locations(module), str(path), "exec"), namespace)
    return namespace


def load_module(relpath, name):
    """Import one module file directly, bypassing mlx_lm/__init__.py."""
    spec = importlib.util.spec_from_file_location(name, ROOT / relpath)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


qwen3_coder = load_module("mlx_lm/tool_parsers/qwen3_coder.py", "qwen3_coder")
infer_tool_parser = lift("mlx_lm/tokenizer_utils.py", {"_infer_tool_parser"})[
    "_infer_tool_parser"
]
SERVER = lift(
    "mlx_lm/server.py",
    {
        "_make_harmony_stream",
        "_select_tool_parser",
        "ToolCallFormatter",
        "_LoudToolCallFormatter",
    },
    {
        "_HarmonyStream": harmony.HarmonyStream,
        "_harmony_parse_tool_call": harmony.parse_tool_call,
    },
)
SERVER_SOURCE = (ROOT / "mlx_lm/server.py").read_text()


class Args:
    """Stand-in for the argparse.Namespace the server hands the selector."""

    def __init__(self, harmony_tool_parser="auto"):
        self.harmony_tool_parser = harmony_tool_parser


class Ctx:
    """Stand-in for mlx_lm.server.GenerationContext, selection fields only."""

    def __init__(self, tool_parser):
        self.tool_parser = tool_parser


def formatter_for(mode, tool_parser, tools=None, streaming=False):
    """Build (harmony_stream, formatter) the way the completion handler does."""
    ctx = Ctx(tool_parser)
    stream = SERVER["_make_harmony_stream"](Args(mode), ctx)
    formatter = SERVER["_LoudToolCallFormatter"](
        SERVER["_select_tool_parser"](stream, ctx), tools, streaming
    )
    return stream, formatter
