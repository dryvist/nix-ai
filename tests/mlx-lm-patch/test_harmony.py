# Copyright © 2026 JacobPEvans. Unit tests for the harmony tool-call parser.
"""Contract tests for harmony.py, run by the `mlx-harmony-parser` nix check.

`captured-gptoss.json` holds three verbatim gpt-oss-120b-MXFP4-Q8 responses
recorded 2026-07-27 against an isolated, ps-proven mlx_lm.server worker — the
same responses that shipped `tool_calls: null` and leaked markup into content.
Everything else is a hand-built malformed/adversarial case.
"""

import json
import unittest
from pathlib import Path

import harmony

CAPTURED = json.loads((Path(__file__).parent / "fixtures/captured-gptoss.json").read_text())


def parse(text, mode="auto"):
    return harmony.parse_text(text, mode)


def chunked(text, size, mode="auto"):
    """Feed `text` through HarmonyStream in fixed-size pieces."""
    stream = harmony.HarmonyStream(mode)
    content = reasoning = ""
    calls = []
    for i in range(0, len(text), size):
        delta = stream.push(text[i : i + size])
        content += delta.content
        reasoning += delta.reasoning
        calls.extend(delta.tool_calls)
    delta = stream.finish()
    return content + delta.content, reasoning + delta.reasoning, calls + list(delta.tool_calls)


class TestCapturedOutput(unittest.TestCase):
    def test_tool_call_after_analysis(self):
        content, reasoning, calls = parse(CAPTURED["toolcall_after_analysis"]["content"])
        self.assertEqual(content, "")
        self.assertIn("get_weather", reasoning)
        self.assertNotIn("<|", reasoning)
        self.assertEqual(len(calls), 1)
        self.assertEqual(
            harmony.parse_tool_call(calls[0]),
            {"name": "get_weather", "arguments": {"city": "Tokyo", "unit": "celsius"}},
        )

    def test_tool_call_paris(self):
        _, _, calls = parse(CAPTURED["toolcall_paris"]["content"])
        self.assertEqual(
            harmony.parse_tool_call(calls[0]),
            {"name": "get_weather", "arguments": {"city": "Paris, France"}},
        )

    def test_plain_completion_content_is_clean(self):
        content, reasoning, calls = parse(CAPTURED["plain_completion"]["content"])
        self.assertEqual(content, "The quick brown fox jumps over the lazy dog.")
        self.assertEqual(calls, [])
        self.assertIn("The user asks", reasoning)
        for blob in (content, reasoning):
            self.assertNotIn("<|", blob)

    def test_streaming_matches_whole_string(self):
        for key, sample in CAPTURED.items():
            for size in (1, 3, 17):
                with self.subTest(sample=key, chunk=size):
                    self.assertEqual(chunked(sample["content"], size), parse(sample["content"]))


class TestMultipleCalls(unittest.TestCase):
    TWO = (
        "<|channel|>analysis<|message|>two cities<|end|>"
        "<|start|>assistant<|channel|>commentary to=functions.get_weather "
        '<|constrain|>json<|message|>{"city": "Tokyo"}<|call|>'
        "<|start|>assistant<|channel|>commentary to=functions.get_weather "
        '<|constrain|>json<|message|>{"city": "Osaka"}<|call|>'
    )

    def test_two_calls_parsed(self):
        content, _, calls = parse(self.TWO)
        self.assertEqual(content, "")
        self.assertEqual(
            [harmony.parse_tool_call(c)["arguments"]["city"] for c in calls],
            ["Tokyo", "Osaka"],
        )

    def test_two_calls_streamed(self):
        self.assertEqual(chunked(self.TWO, 5), parse(self.TWO))

    def test_call_then_final(self):
        text = self.TWO + "<|start|>assistant<|channel|>final<|message|>done<|return|>"
        content, _, calls = parse(text)
        self.assertEqual(content, "done")
        self.assertEqual(len(calls), 2)


class TestDegradation(unittest.TestCase):
    def test_truncated_json_falls_back_to_content(self):
        text = (
            "<|channel|>commentary to=functions.get_weather "
            '<|constrain|>json<|message|>{"city": "Tok'
        )
        content, _, calls = parse(text)
        self.assertEqual(calls, [])
        self.assertIn('{"city": "Tok', content)

    def test_no_markup_passes_through(self):
        content, reasoning, calls = parse("Just a plain answer.")
        self.assertEqual(content, "Just a plain answer.")
        self.assertEqual((reasoning, calls), ("", []))

    def test_header_without_message_is_verbatim(self):
        content, _, calls = parse("<|channel|>analysis")
        self.assertEqual(content, "<|channel|>analysis")
        self.assertEqual(calls, [])

    def test_analysis_without_tool_call(self):
        content, reasoning, calls = parse("<|channel|>analysis<|message|>hmm<|end|>")
        self.assertEqual((content, reasoning, calls), ("", "hmm", []))

    def test_unterminated_analysis_still_reasoning(self):
        content, reasoning, _ = parse("<|channel|>analysis<|message|>hmm")
        self.assertEqual((content, reasoning), ("", "hmm"))

    def test_unknown_channel_becomes_content(self):
        content, _, calls = parse("<|channel|>weird<|message|>text<|end|>")
        self.assertEqual((content, calls), ("text", []))

    def test_commentary_without_recipient_is_content(self):
        content, _, calls = parse("<|channel|>commentary<|message|>preamble<|end|>")
        self.assertEqual((content, calls), ("preamble", []))

    def test_mode_off_never_engages(self):
        raw = CAPTURED["plain_completion"]["content"]
        self.assertEqual(parse(raw, mode="off"), (raw, "", []))

    def test_mode_on_tolerates_plain_text(self):
        self.assertEqual(parse("no markup here", mode="on"), ("no markup here", "", []))

    def test_template_order_recipient_before_channel(self):
        text = (
            "<|start|>assistant to=functions.get_weather<|channel|>commentary "
            '<|message|>{"city": "Kyoto"}<|call|>'
        )
        _, _, calls = parse(text)
        self.assertEqual(harmony.parse_tool_call(calls[0])["arguments"], {"city": "Kyoto"})

    def test_empty_arguments(self):
        text = "<|channel|>commentary to=functions.ping<|message|>{}<|call|>"
        _, _, calls = parse(text)
        self.assertEqual(harmony.parse_tool_call(calls[0]), {"name": "ping", "arguments": {}})

    def test_empty_input(self):
        self.assertEqual(parse(""), ("", "", []))


class TestParseToolCall(unittest.TestCase):
    def test_rejects_missing_body(self):
        with self.assertRaises(ValueError):
            harmony.parse_tool_call("<|channel|>commentary to=functions.x")

    def test_rejects_missing_recipient(self):
        with self.assertRaises(ValueError):
            harmony.parse_tool_call("<|channel|>final<|message|>{}")

    def test_rejects_non_object_arguments(self):
        with self.assertRaises(ValueError):
            harmony.parse_tool_call("<|channel|>commentary to=functions.x<|message|>[1]")

    def test_rejects_bad_json(self):
        with self.assertRaises((ValueError, json.JSONDecodeError)):
            harmony.parse_tool_call("<|channel|>commentary to=functions.x<|message|>{oops")

    def test_bare_recipient_without_namespace(self):
        parsed = harmony.parse_tool_call("<|channel|>commentary to=lookup<|message|>{}")
        self.assertEqual(parsed["name"], "lookup")


if __name__ == "__main__":
    unittest.main()
