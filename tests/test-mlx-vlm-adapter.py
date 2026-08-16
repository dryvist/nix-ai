#!/usr/bin/env python3
"""Unit tests for modules/mlx/scripts/mlx-vlm-adapter.py request handling.

Covers the parts a live-model smoke test does NOT reach: message flattening,
image payload handling, and the refusal of non-URL image references. The
generation path itself needs a real model and is exercised by hand against a
running adapter; everything here is pure and runs without mlx installed.

The module imports mlx_vlm lazily INSIDE its functions precisely so this file
can import it without the dependency present. If that ever moves to a
top-level import, these tests fail at import time — which is the intended
signal, not a reason to add a mock.
"""

from __future__ import annotations

import base64
import importlib.util
import json
import pathlib
import sys
import tempfile

ADAPTER = (
    pathlib.Path(__file__).resolve().parent.parent
    / "modules"
    / "mlx"
    / "scripts"
    / "mlx-vlm-adapter.py"
)

spec = importlib.util.spec_from_file_location("mlx_vlm_adapter", ADAPTER)
assert spec and spec.loader, f"cannot load {ADAPTER}"
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)

failures: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"ok   - {label}")
    else:
        print(f"FAIL - {label} {detail}")
        failures.append(label)


# --- parse_messages -------------------------------------------------------

prompt, images, systems = adapter.parse_messages(
    [
        {"role": "system", "content": "You transcribe documents."},
        {
            "role": "user",
            "content": [
                {"type": "image_url", "image_url": {"url": "data:image/png;base64,AAAA"}},
                {"type": "text", "text": "Free OCR."},
            ],
        },
    ]
)
check("text parts are collected", prompt == "Free OCR.", f"got {prompt!r}")
check("image urls are collected", images == ["data:image/png;base64,AAAA"], f"got {images!r}")
check("system parts stay separate", systems == ["You transcribe documents."], f"got {systems!r}")

# A plain string content body is the common single-turn shape and must not be
# treated as an iterable of parts.
prompt, images, _ = adapter.parse_messages([{"role": "user", "content": "just text"}])
check("string content is not iterated as parts", prompt == "just text" and images == [], f"got {prompt!r}/{images!r}")

# An image part with an empty url would otherwise produce a bogus image entry
# and desync the image-token count the chat template inserts.
_, images, _ = adapter.parse_messages(
    [{"role": "user", "content": [{"type": "image_url", "image_url": {"url": ""}}]}]
)
check("empty image url is dropped", images == [], f"got {images!r}")

# --- materialize_image ----------------------------------------------------

with tempfile.TemporaryDirectory() as tmp:
    payload = b"\x89PNG\r\n\x1a\nsentinel"
    uri = "data:image/png;base64," + base64.b64encode(payload).decode()
    path = adapter.materialize_image(uri, tmp, 0)
    check("data uri is decoded to disk", pathlib.Path(path).read_bytes() == payload)
    check("suffix comes from the mime type", path.endswith(".png"), f"got {path!r}")

    # The declared mime subtype is caller-supplied, so it must never reach the
    # filename unmapped. An unknown or hostile subtype falls back to png rather
    # than putting user-controlled text in a path.
    for subtype, expected in (("jpeg", ".jpg"), ("webp", ".webp"), ("totally-made-up", ".png")):
        p = adapter.materialize_image(f"data:image/{subtype};base64,{base64.b64encode(payload).decode()}", tmp, 2)
        check(f"subtype {subtype!r} maps to {expected}", p.endswith(expected), f"got {p!r}")

    hostile = adapter.materialize_image(
        "data:image/..;base64," + base64.b64encode(payload).decode(), tmp, 3
    )
    check(
        "traversal-shaped subtype does not reach the filename",
        hostile.endswith(".png") and ".." not in pathlib.Path(hostile).name,
        f"got {hostile!r}",
    )

    # Only data: URIs are accepted. A filesystem path would read any file the
    # worker can reach; an http(s) URL would make the worker issue requests
    # from inside the serving host, reaching internal services the caller
    # cannot address directly. Both are refused rather than resolved, so both
    # are pinned here — an accidental re-introduction of remote fetch is the
    # regression this list exists to catch.
    for hostile in (
        "/etc/passwd",
        "../../etc/passwd",
        "file:///etc/passwd",
        "http://169.254.169.254/latest/meta-data/",
        "https://example.internal/secret.png",
        "",
    ):
        try:
            adapter.materialize_image(hostile, tmp, 1)
            check(f"refuses non-url image ref {hostile!r}", False, "no exception raised")
        except ValueError:
            check(f"refuses non-url image ref {hostile!r}", True)

# --- sse_body (stream=true wire shape) ------------------------------------
#
# The adapter used to answer stream=true with a 400, which made it unusable
# from any chat UI that streams by default. These assert the SSE shape an
# OpenAI client actually parses — a body that merely "looks streamed" but omits
# the [DONE] sentinel or the stop frame hangs the client instead of erroring,
# which is the failure mode worth pinning.

body = adapter.sse_body("HELLO OCR", "some/model-id", 1_700_000_000.5).decode()

check("stream body terminates with the DONE sentinel", body.endswith("data: [DONE]\n\n"), f"got {body[-40:]!r}")

frames = [ln[len("data: "):] for ln in body.split("\n\n") if ln.startswith("data: ") and ln != "data: [DONE]"]
check("stream body carries exactly two json frames", len(frames) == 2, f"got {len(frames)}")

first = json.loads(frames[0])
last = json.loads(frames[1])

check("content rides in the first frame's delta", first["choices"][0]["delta"].get("content") == "HELLO OCR", f"got {first['choices'][0]['delta']!r}")
check("first frame has no finish_reason", first["choices"][0]["finish_reason"] is None, f"got {first['choices'][0]['finish_reason']!r}")
check("final frame finishes with stop", last["choices"][0]["finish_reason"] == "stop", f"got {last['choices'][0]['finish_reason']!r}")
check("final frame carries no extra content", last["choices"][0]["delta"] == {}, f"got {last['choices'][0]['delta']!r}")
check("chunk object type is the streaming one", first["object"] == "chat.completion.chunk", f"got {first['object']!r}")
check("model id is echoed back", first["model"] == "some/model-id", f"got {first['model']!r}")
check("both frames share one completion id", first["id"] == last["id"], f"got {first['id']!r}/{last['id']!r}")

# A body whose content is empty still has to be a well-formed stream: a client
# that gets no frames at all waits for the socket rather than returning "".
empty = adapter.sse_body("", "m", 0.0).decode()
check("empty completion still emits a well-formed stream", empty.endswith("data: [DONE]\n\n") and empty.count("data: ") == 3, f"got {empty!r}")

# --- constants ------------------------------------------------------------

check("body cap is set and sane", 1024 * 1024 <= adapter.MAX_BODY_BYTES <= 512 * 1024 * 1024)

print(f"\n{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
