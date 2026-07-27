# Copyright © 2026 JacobPEvans. Injected into mlx_lm/tool_parsers/harmony.py.
"""Translate OpenAI *harmony* channel markup into OpenAI API response fields.

gpt-oss emits its whole turn as harmony channels::

    <|channel|>analysis<|message|>thinking...<|end|>
    <|start|>assistant<|channel|>commentary to=functions.NAME \
        <|constrain|>json<|message|>{"city": "Tokyo"}<|call|>
    <|start|>assistant<|channel|>final<|message|>answer<|return|>

mlx-lm infers no tool parser for that chat template, so `has_tool_calling`
is False, every marker lands verbatim in `content`, and `tool_calls` stays
null.  `HarmonyStream` segments the text incrementally instead: `final` ->
content, `analysis` -> reasoning_content, `commentary to=functions.X` -> a
real tool call.  Anything it cannot understand is emitted verbatim as
content, so a malformed or truncated turn degrades to today's behaviour
rather than raising into the generation loop.
"""

import json
import re
from typing import List, NamedTuple, Optional, Tuple

MESSAGE = "<|message|>"
CHANNEL = "<|channel|>"
START = "<|start|>"
# End of one harmony message. START is included because a new message may
# begin without the previous one being closed.
TERMINATORS = ("<|end|>", "<|call|>", "<|return|>", START)
_MAX_MARKER = max(len(m) for m in TERMINATORS + (MESSAGE, CHANNEL))

_RECIPIENT_RE = re.compile(r"to=([A-Za-z0-9_.\-]+)")
_CHANNEL_RE = re.compile(r"<\|channel\|>\s*([A-Za-z0-9_-]+)")

# Module contract shared with the other mlx_lm.tool_parsers. Not registered in
# _infer_tool_parser: the harmony tool-call header is variable text, so the
# token-sequence state machine cannot bound it — HarmonyStream does that.
tool_call_start = CHANNEL + "commentary"
tool_call_end = "<|call|>"


def parse_tool_call(text: str, tools=None) -> dict:
    """Parse one harmony tool-call message into ``{name, arguments}``.

    Accepts the raw segment, with or without its leading/trailing markers.
    Raises ValueError/JSONDecodeError on anything else — the contract
    ``mlx_lm.server.ToolCallFormatter`` already catches.
    """
    head, sep, body = text.partition(MESSAGE)
    if not sep:
        raise ValueError("No harmony message body.")
    recipient = _RECIPIENT_RE.search(head)
    if recipient is None:
        raise ValueError("No harmony tool recipient.")
    name = recipient.group(1)
    if name.startswith("functions."):
        name = name[len("functions.") :]
    body = body.strip()
    for term in TERMINATORS:
        if body.endswith(term):
            body = body[: -len(term)].strip()
    arguments = json.loads(body) if body else {}
    if not isinstance(arguments, dict):
        raise ValueError("Harmony tool arguments must be a JSON object.")
    return {"name": name, "arguments": arguments}


class Delta(NamedTuple):
    """What one ``push``/``finish`` produced. All fields may be empty."""

    content: str = ""
    reasoning: str = ""
    tool_calls: Tuple[str, ...] = ()


_EMPTY = Delta()


def _held_suffix(buf: str) -> int:
    """Length of the trailing run that could still grow into a marker."""
    for k in range(min(len(buf), _MAX_MARKER - 1), 0, -1):
        tail = buf[-k:]
        if any(t.startswith(tail) for t in TERMINATORS):
            return k
    return 0


def _find_terminator(buf: str) -> Tuple[int, str]:
    best, best_term = -1, ""
    for term in TERMINATORS:
        i = buf.find(term)
        if i >= 0 and (best < 0 or i < best):
            best, best_term = i, term
    return best, best_term


class HarmonyStream:
    """Incremental harmony segmenter. One instance per completion."""

    def __init__(self, mode: str = "auto"):
        self._engaged = mode == "on"
        self._deciding = mode == "auto"
        self._buf = ""
        self._channel: Optional[str] = None  # None => scanning a header
        self._recipient: Optional[str] = None
        self._header = ""
        self._body = ""

    def push(self, text: str) -> Delta:
        self._buf += text
        if self._deciding and not self._decide():
            return _EMPTY
        if not self._engaged:
            out, self._buf = self._buf, ""
            return Delta(content=out)
        return self._drain(final=False)

    def finish(self) -> Delta:
        if self._deciding:
            self._deciding = False
            self._engaged = False
        if not self._engaged:
            out, self._buf = self._buf, ""
            return Delta(content=out)
        return self._drain(final=True)

    # -- internals ---------------------------------------------------------
    def _decide(self) -> bool:
        """In auto mode, engage only when the turn opens with harmony markup."""
        head = self._buf.lstrip()
        if not head:
            return False
        for prefix in (CHANNEL, START):
            if head.startswith(prefix):
                self._engaged, self._deciding = True, False
                return True
            if prefix.startswith(head):
                return False  # still could grow into a marker
        self._engaged, self._deciding = False, False
        return True

    def _drain(self, final: bool) -> Delta:
        content, reasoning, calls = "", "", []
        while True:
            if self._channel is None:
                if not self._scan_header(final):
                    break
                continue
            done, text, kind = self._scan_body(final)
            if kind == "content":
                content += text
            elif kind == "reasoning":
                reasoning += text
            elif kind == "tool":
                calls.append(text)
            if not done:
                break
        return Delta(content, reasoning, tuple(calls))

    def _scan_header(self, final: bool) -> bool:
        i = self._buf.find(MESSAGE)
        if i < 0:
            if final and self._buf:
                # Header never completed — hand it back verbatim rather than
                # swallowing it. The caller sees today's leaky-but-lossless text.
                self._header, self._buf = self._buf, ""
                self._channel, self._recipient = "", None
                return True
            return False
        self._header = self._buf[:i]
        self._buf = self._buf[i + len(MESSAGE) :]
        match = _CHANNEL_RE.search(self._header)
        self._channel = match.group(1) if match else ""
        recipient = _RECIPIENT_RE.search(self._header)
        self._recipient = recipient.group(1) if recipient else None
        return True

    def _scan_body(self, final: bool) -> Tuple[bool, str, str]:
        """Consume body text. Returns (message_complete, text, kind)."""
        i, term = _find_terminator(self._buf)
        if i < 0:
            body, self._buf = self._buf, ""
            if not final:
                hold = _held_suffix(body)
                if hold:
                    body, self._buf = body[:-hold], body[-hold:]
            return (False,) + self._consume(body, closed=final)
        body = self._buf[:i]
        # START opens the next message, so leave it in the buffer.
        drop = 0 if term == START else len(term)
        self._buf = self._buf[i + drop :]
        result = self._consume(body, closed=True)
        self._channel, self._recipient, self._header, self._body = None, None, "", ""
        return (True,) + result

    def _consume(self, body: str, closed: bool) -> Tuple[str, str]:
        """Route one body fragment. Tool bodies buffer until the message ends."""
        if self._recipient is not None:
            self._body += body
            if not closed:
                return "", ""
            raw = self._header + MESSAGE + self._body
            try:
                parse_tool_call(raw)
            except (ValueError, json.JSONDecodeError):
                return raw, "content"  # truncated/malformed -> verbatim
            return raw, "tool"
        if self._channel == "analysis":
            return body, "reasoning"
        if self._channel in ("final", "commentary", ""):
            # "" is the degraded no-header case; commentary without a recipient
            # is a user-visible preamble in the harmony spec.
            return (self._header + body, "content") if self._channel == "" else (
                body,
                "content",
            )
        return body, "content"


def parse_text(text: str, mode: str = "auto") -> Tuple[str, str, List[str]]:
    """Whole-string convenience wrapper around HarmonyStream."""
    stream = HarmonyStream(mode)
    first, second = stream.push(text), stream.finish()
    return (
        first.content + second.content,
        first.reasoning + second.reasoning,
        list(first.tool_calls + second.tool_calls),
    )
