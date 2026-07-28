# Copyright © 2026 JacobPEvans. Regression tests for harmony parser SELECTION.
"""The harmony parser must stay out of the way of models that have their own.

test_harmony.py only ever proved harmony *works*. It cannot see the failure this
file exists for: `--harmony-tool-parser auto` replacing a non-harmony model's
correctly inferred parser. That shipped, and on mlx-community/Qwen3.6-35B-A3B-4bit
it made every well-formed `<tool_call>` raise `ValueError: No harmony message
body.`; the formatter swallowed it, `tool_calls` came back empty, and the key was
omitted while `finish_reason` already said "tool_calls" — a turn with neither
tool calls nor content.

Everything under test is the real thing, pulled out of the patched wheel by
wheel_under_test.py.
"""

import json
import unittest

from wheel_under_test import (
    FIXTURE,
    SERVER,
    SERVER_SOURCE,
    Ctx,
    formatter_for,
    infer_tool_parser,
    qwen3_coder,
)

import harmony


class TestPremise(unittest.TestCase):
    """The live case: this template really does infer a real parser."""

    def test_qwen_template_infers_qwen3_coder(self):
        self.assertEqual(
            infer_tool_parser(FIXTURE["chat_template_excerpt"]),
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
        stream, _ = formatter_for("auto", qwen3_coder.parse_tool_call)
        self.assertIsNone(stream)

    def test_selected_parser_is_the_inferred_one(self):
        _, formatter = formatter_for("auto", qwen3_coder.parse_tool_call)
        self.assertIs(formatter._tool_parser, qwen3_coder.parse_tool_call)

    def test_tool_calls_array_is_populated(self):
        _, formatter = formatter_for("auto", qwen3_coder.parse_tool_call)
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
        _, formatter = formatter_for("auto", qwen3_coder.parse_tool_call, tools=tools)
        formatted = formatter([FIXTURE["tool_text"]])
        self.assertEqual(json.loads(formatted[0]["function"]["arguments"])["city"], "Tokyo")


class TestAutoStillCoversHarmony(unittest.TestCase):
    """gpt-oss infers nothing, which is exactly when auto must engage."""

    def test_engages_when_no_parser_was_inferred(self):
        stream, formatter = formatter_for("auto", None)
        self.assertIsNotNone(stream)
        self.assertIs(formatter._tool_parser, harmony.parse_tool_call)

    def test_gptoss_template_infers_nothing(self):
        # The premise of the clause above, checked against upstream's own logic.
        self.assertIsNone(
            infer_tool_parser(
                "<|start|>assistant<|channel|>commentary to=functions.x"
                "<|constrain|>json<|message|>{}<|call|>"
            )
        )

    def test_harmony_tool_call_still_reaches_the_client(self):
        _, formatter = formatter_for("auto", None)
        raw = (
            "<|channel|>commentary to=functions.get_weather "
            '<|constrain|>json<|message|>{"city": "Tokyo"}<|call|>'
        )
        formatted = formatter([raw])
        self.assertEqual(formatted[0]["function"]["name"], "get_weather")


class TestExplicitModes(unittest.TestCase):
    """`on` and `off` keep the meaning they shipped with."""

    def test_on_overrides_an_inferred_parser(self):
        stream, formatter = formatter_for("on", qwen3_coder.parse_tool_call)
        self.assertIsNotNone(stream)
        self.assertIs(formatter._tool_parser, harmony.parse_tool_call)

    def test_off_never_engages_even_without_a_parser(self):
        stream, formatter = formatter_for("off", None)
        self.assertIsNone(stream)
        self.assertIsNone(formatter._tool_parser)

    def test_missing_flag_defaults_to_auto(self):
        ctx = Ctx(qwen3_coder.parse_tool_call)
        self.assertIsNone(SERVER["_make_harmony_stream"](object(), ctx))


class TestPatchedHandlerWiring(unittest.TestCase):
    """The handler must actually use the gated selection, not the old ternary."""

    def test_handler_builds_the_stream_with_ctx(self):
        self.assertIn(
            "_make_harmony_stream(self.response_generator.cli_args, ctx)", SERVER_SOURCE
        )

    def test_handler_selects_through_the_helper(self):
        self.assertIn("_select_tool_parser(harmony_stream, ctx)", SERVER_SOURCE)

    def test_ungated_ternary_is_gone(self):
        self.assertNotIn(
            "_harmony_parse_tool_call if harmony_stream is not None else ctx.tool_parser,",
            SERVER_SOURCE,
        )

    def test_finish_reason_requires_an_emitted_call(self):
        self.assertIn(
            'if finish_reason == "stop" and made_tool_call and tool_formatter.emitted:',
            SERVER_SOURCE,
        )


if __name__ == "__main__":
    unittest.main()
