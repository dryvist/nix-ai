# Copyright © 2026 JacobPEvans. Regression tests for harmony parser SELECTION.
"""The harmony parser must stay out of the way of models that have their own.

The parser tests in test_harmony.py only ever proved harmony *works*. They
cannot catch the failure this file exists for: `--harmony-tool-parser auto`
replacing a non-harmony model's correctly inferred parser. That shipped, and on
mlx-community/Qwen3.6-35B-A3B-4bit it made every well-formed `<tool_call>` raise
`ValueError: No harmony message body.`; the formatter swallowed it, `tool_calls`
came back empty, and the key was omitted while `finish_reason` already said
"tool_calls" — a turn with neither tool calls nor content.

So these tests drive the real code, not a re-statement of it. Everything under
test is pulled out of the *patched wheel* named by $MLX_LM_ROOT:

  * `_infer_tool_parser`  from mlx_lm/tokenizer_utils.py  (picks qwen3_coder)
  * `parse_tool_call`     from mlx_lm/tool_parsers/qwen3_coder.py
  * `_make_harmony_stream`, `_select_tool_parser`, `ToolCallFormatter`,
    `_LoudToolCallFormatter` from the patched mlx_lm/server.py

Those modules import mlx at package level, which does not exist off Apple
silicon, so each definition is lifted out of the real source with `ast` rather
than imported. A rename or deletion upstream fails the extraction loudly
instead of quietly testing nothing.
"""

import ast
import importlib.util
import json
import logging
import os
import unittest
import uuid
from pathlib import Path

import harmony

FIXTURE = json.loads((Path(__file__).parent / "fixtures/qwen-non-harmony.json").read_text())

MLX_LM_ROOT = os.environ.get("MLX_LM_ROOT")
if not MLX_LM_ROOT:
    raise RuntimeError(
        "MLX_LM_ROOT must point at an unpacked patched mlx-lm wheel; these tests "
        "verify the real server.py selection code, not a copy of it."
    )
_ROOT = Path(MLX_LM_ROOT)


def _lift(relpath, names, extra_globals=None):
    """Execute just `names` from a source file, without importing its package."""
    path = _ROOT / relpath
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


def _load_module(relpath, name):
    """Import one module file directly, bypassing mlx_lm/__init__.py."""
    spec = importlib.util.spec_from_file_location(name, _ROOT / relpath)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


qwen3_coder = _load_module("mlx_lm/tool_parsers/qwen3_coder.py", "qwen3_coder")
_infer_tool_parser = _lift("mlx_lm/tokenizer_utils.py", {"_infer_tool_parser"})[
    "_infer_tool_parser"
]
_server = _lift(
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


class _Args:
    """Stand-in for the argparse.Namespace the server hands the selector."""

    def __init__(self, harmony_tool_parser="auto"):
        self.harmony_tool_parser = harmony_tool_parser


class _Ctx:
    """Stand-in for mlx_lm.server.GenerationContext, selection fields only."""

    def __init__(self, tool_parser):
        self.tool_parser = tool_parser


def _formatter_for(mode, tool_parser, tools=None, streaming=False):
    """Build the formatter exactly the way the completion handler does."""
    ctx = _Ctx(tool_parser)
    stream = _server["_make_harmony_stream"](_Args(mode), ctx)
    formatter = _server["_LoudToolCallFormatter"](
        _server["_select_tool_parser"](stream, ctx), tools, streaming
    )
    return stream, formatter


class TestPremise(unittest.TestCase):
    """The live case: this template really does infer a real parser."""

    def test_qwen_template_infers_qwen3_coder(self):
        self.assertEqual(
            _infer_tool_parser(FIXTURE["chat_template_excerpt"]),
            FIXTURE["expected_parser"],
        )

    def test_qwen_parser_parses_its_own_tool_call(self):
        self.assertEqual(
            qwen3_coder.parse_tool_call(FIXTURE["tool_text"]),
            FIXTURE["expected_tool_call"],
        )

    def test_harmony_cannot_read_a_qwen_tool_call(self):
        # Why substituting the parser is fatal rather than merely wrong.
        with self.assertRaises(ValueError):
            harmony.parse_tool_call(FIXTURE["tool_text"])


class TestAutoLeavesInferredParserAlone(unittest.TestCase):
    """auto + a model with its own parser => that parser, and calls come out."""

    def test_no_harmony_stream_is_created(self):
        stream, _ = _formatter_for("auto", qwen3_coder.parse_tool_call)
        self.assertIsNone(stream)

    def test_selected_parser_is_the_inferred_one(self):
        _, formatter = _formatter_for("auto", qwen3_coder.parse_tool_call)
        self.assertIs(formatter._tool_parser, qwen3_coder.parse_tool_call)

    def test_tool_calls_array_is_populated(self):
        _, formatter = _formatter_for("auto", qwen3_coder.parse_tool_call)
        formatted = formatter([FIXTURE["tool_text"]])
        self.assertEqual(len(formatted), 1)
        self.assertEqual(formatted[0]["type"], "function")
        self.assertEqual(formatted[0]["function"]["name"], "get_weather")
        self.assertEqual(
            json.loads(formatted[0]["function"]["arguments"]),
            FIXTURE["expected_tool_call"]["arguments"],
        )
        self.assertEqual(formatter.emitted, 1)
        self.assertEqual(formatter.drain_unparsed(), "")

    def test_tools_schema_is_threaded_through(self):
        tools = [
            {
                "function": {
                    "name": "get_weather",
                    "parameters": {"properties": {"city": {"type": "string"}}},
                }
            }
        ]
        _, formatter = _formatter_for("auto", qwen3_coder.parse_tool_call, tools=tools)
        formatted = formatter([FIXTURE["tool_text"]])
        self.assertEqual(json.loads(formatted[0]["function"]["arguments"])["city"], "Tokyo")


class TestAutoStillCoversHarmony(unittest.TestCase):
    """gpt-oss infers nothing, which is exactly when auto must engage."""

    def test_engages_when_no_parser_was_inferred(self):
        stream, formatter = _formatter_for("auto", None)
        self.assertIsNotNone(stream)
        self.assertIs(formatter._tool_parser, harmony.parse_tool_call)

    def test_gptoss_template_infers_nothing(self):
        # The premise of the clause above, checked against upstream's own logic.
        self.assertIsNone(
            _infer_tool_parser(
                "<|start|>assistant<|channel|>commentary to=functions.x"
                "<|constrain|>json<|message|>{}<|call|>"
            )
        )

    def test_harmony_tool_call_still_reaches_the_client(self):
        _, formatter = _formatter_for("auto", None)
        raw = (
            "<|channel|>commentary to=functions.get_weather "
            '<|constrain|>json<|message|>{"city": "Tokyo"}<|call|>'
        )
        formatted = formatter([raw])
        self.assertEqual(formatted[0]["function"]["name"], "get_weather")


class TestExplicitModes(unittest.TestCase):
    """`on` and `off` keep the meaning they shipped with."""

    def test_on_overrides_an_inferred_parser(self):
        stream, formatter = _formatter_for("on", qwen3_coder.parse_tool_call)
        self.assertIsNotNone(stream)
        self.assertIs(formatter._tool_parser, harmony.parse_tool_call)

    def test_off_never_engages_even_without_a_parser(self):
        stream, formatter = _formatter_for("off", None)
        self.assertIsNone(stream)
        self.assertIsNone(formatter._tool_parser)

    def test_missing_flag_defaults_to_auto(self):
        ctx = _Ctx(qwen3_coder.parse_tool_call)
        self.assertIsNone(_server["_make_harmony_stream"](object(), ctx))


class TestFailedParseIsNotSilence(unittest.TestCase):
    """A parse failure must not look like "the model made no tool call"."""

    def test_unparsed_text_is_kept_for_content(self):
        _, formatter = _formatter_for("auto", None)  # harmony parser, qwen input
        with self.assertLogs(level="ERROR"):
            formatted = formatter([FIXTURE["tool_text"]])
        self.assertEqual(formatted, [])
        self.assertEqual(formatter.emitted, 0)
        self.assertEqual(formatter.drain_unparsed(), FIXTURE["tool_text"])

    def test_drain_is_not_repeated(self):
        _, formatter = _formatter_for("auto", None)
        with self.assertLogs(level="ERROR"):
            formatter([FIXTURE["tool_text"]])
        formatter.drain_unparsed()
        self.assertEqual(formatter.drain_unparsed(), "")

    def test_a_good_call_beside_a_bad_one_still_emits(self):
        _, formatter = _formatter_for("auto", qwen3_coder.parse_tool_call)
        with self.assertLogs(level="ERROR"):
            formatted = formatter(["<function=broken", FIXTURE["tool_text"]])
        self.assertEqual(len(formatted), 1)
        self.assertEqual(formatter.emitted, 1)
        self.assertEqual(formatter.drain_unparsed(), "<function=broken")

    def test_empty_input_emits_nothing_and_logs_nothing(self):
        _, formatter = _formatter_for("auto", qwen3_coder.parse_tool_call)
        self.assertEqual(formatter([]), [])
        self.assertEqual(formatter(None), [])
        self.assertEqual(formatter.emitted, 0)


class TestPatchedHandlerWiring(unittest.TestCase):
    """The handler must actually use the gated selection, not the old ternary."""

    SOURCE = None

    @classmethod
    def setUpClass(cls):
        cls.SOURCE = (_ROOT / "mlx_lm/server.py").read_text()

    def test_handler_builds_the_stream_with_ctx(self):
        self.assertIn(
            "_make_harmony_stream(self.response_generator.cli_args, ctx)", self.SOURCE
        )

    def test_handler_selects_through_the_helper(self):
        self.assertIn("_select_tool_parser(harmony_stream, ctx)", self.SOURCE)

    def test_ungated_ternary_is_gone(self):
        self.assertNotIn(
            "_harmony_parse_tool_call if harmony_stream is not None else ctx.tool_parser,",
            self.SOURCE,
        )

    def test_finish_reason_requires_an_emitted_call(self):
        self.assertIn(
            'if finish_reason == "stop" and made_tool_call and tool_formatter.emitted:',
            self.SOURCE,
        )


if __name__ == "__main__":
    unittest.main()
