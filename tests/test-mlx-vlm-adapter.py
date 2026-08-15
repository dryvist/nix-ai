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

# --- constants ------------------------------------------------------------

check("body cap is set and sane", 1024 * 1024 <= adapter.MAX_BODY_BYTES <= 512 * 1024 * 1024)

print(f"\n{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
