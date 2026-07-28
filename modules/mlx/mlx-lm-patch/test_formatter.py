# Copyright © 2026 JacobPEvans. A failed tool-call parse must not become silence.
"""Upstream drops a tool call whose parser raised, and the drop is invisible.

`ToolCallFormatter` logs a warning and skips. `generate_response` then omits
`tool_calls` because the list is empty. A turn where every call failed therefore
reaches the client with no tool calls AND no content — indistinguishable from a
turn the model never made. That is how the selection defect stayed hidden behind
a log line nobody was reading.

`_LoudToolCallFormatter` keeps the unparsed text so the handler can hand it back
as content, and counts what actually went out so `finish_reason` cannot claim
"tool_calls" with none attached.
"""

import unittest

from wheel_under_test import FIXTURE, formatter_for, qwen3_coder


class TestFailedParseIsNotSilence(unittest.TestCase):
    def test_unparsed_text_is_kept_for_content(self):
        # harmony parser against qwen input: the live mismatch, in miniature.
        _, formatter = formatter_for("auto", None)
        with self.assertLogs(level="ERROR"):
            formatted = formatter([FIXTURE["tool_text"]])
        self.assertEqual(formatted, [])
        self.assertEqual(formatter.emitted, 0)
        self.assertEqual(formatter.drain_unparsed(), FIXTURE["tool_text"])

    def test_drain_is_not_repeated(self):
        _, formatter = formatter_for("auto", None)
        with self.assertLogs(level="ERROR"):
            formatter([FIXTURE["tool_text"]])
        formatter.drain_unparsed()
        self.assertEqual(formatter.drain_unparsed(), "")

    def test_a_good_call_beside_a_bad_one_still_emits(self):
        _, formatter = formatter_for("auto", qwen3_coder.parse_tool_call)
        with self.assertLogs(level="ERROR"):
            formatted = formatter(["<function=broken", FIXTURE["tool_text"]])
        self.assertEqual(len(formatted), 1)
        self.assertEqual(formatter.emitted, 1)
        self.assertEqual(formatter.drain_unparsed(), "<function=broken")

    def test_emitted_accumulates_across_streaming_chunks(self):
        # The streaming path calls the formatter once per chunk, and
        # finish_reason is decided from the running total.
        _, formatter = formatter_for("auto", qwen3_coder.parse_tool_call, streaming=True)
        formatter([FIXTURE["tool_text"]])
        formatter([FIXTURE["tool_text"]])
        self.assertEqual(formatter.emitted, 2)

    def test_empty_input_emits_nothing_and_logs_nothing(self):
        _, formatter = formatter_for("auto", qwen3_coder.parse_tool_call)
        self.assertEqual(formatter([]), [])
        self.assertEqual(formatter(None), [])
        self.assertEqual(formatter.emitted, 0)
        self.assertEqual(formatter.drain_unparsed(), "")


if __name__ == "__main__":
    unittest.main()
