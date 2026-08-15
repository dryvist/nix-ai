#!/usr/bin/env python3
"""OpenAI-compatible single-model server for mlx-vlm vision-language models.

WHY THIS EXISTS INSTEAD OF mlx_vlm.server
-----------------------------------------
mlx_vlm ships its own server, and for most vision models it is the right
answer. It cannot serve every model: mlx_vlm.server runs generation on a
worker thread, and a model whose own implementation forces a GPU sync during
input embedding then dies with

    RuntimeError: There is no Stream(gpu, 2) in current thread

Measured against mlx-vlm 0.6.13 (the latest release) with
mlx-community/Unlimited-OCR-bf16: the model loads, one-shot
mlx_vlm.generate() returns correct OCR, and every request through
mlx_vlm.server fails with the above. --max-num-seqs 1 does not avoid it,
because the failure is the threading model rather than batch width.

So this adapter keeps the exact wire contract mlx_vlm.server offers and drops
the only part that breaks: it runs generation on the main thread, one request
at a time, via the same mlx_vlm.generate() call the model card documents.

Serialization is a feature here, not a limitation to remove later. A
full-page VLM decode saturates the GPU on its own, so a second concurrent
request would only trade latency for latency. Catalog entries served through
this adapter therefore pin concurrencyLimit = 1, and the proxy must not admit
more than the worker serves — an over-admitting proxy is what turns excess
requests into HTTP 429s.

CONTRACT
--------
Argument-compatible with mlx_vlm.server for the flags llama-swap's cmd builder
emits (--model/--port/--host/--trust-remote-code), so it is a drop-in behind
the same backend selection. Serves:

    GET  /health              liveness, cheap
    GET  /v1/models           the one loaded model
    POST /v1/chat/completions OpenAI chat completions, image content parts

Images arrive as OpenAI image_url parts and must be data: URIs — see
materialize_image() for why remote URLs are refused rather than fetched. They
are written to a temp file because mlx_vlm.generate() takes paths.

NOT SUPPORTED, deliberately: streaming, tool calls, multi-model hosting,
audio/video. llama-swap already supplies multi-model hosting and idle
eviction; duplicating any of it here would create a second lifecycle owner.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

DATA_URI = re.compile(r"^data:(?P<mime>[\w./+-]+);base64,(?P<payload>.*)$", re.DOTALL)

# A page image is the payload here, so the default body cap has to clear a
# rasterized page with room to spare. 64 MiB holds a 300-dpi colour A4 PNG
# several times over, while still refusing a body that could only be a mistake
# or an attempt to exhaust memory.
MAX_BODY_BYTES = 64 * 1024 * 1024

# Closed set of filename extensions. See materialize_image(): the declared mime
# subtype is caller-supplied, so it is mapped through this table instead of
# reaching a path directly.
SUFFIX_BY_MIME_SUBTYPE = {
    "png": "png",
    "jpeg": "jpg",
    "jpg": "jpg",
    "webp": "webp",
    "gif": "gif",
    "bmp": "bmp",
    "tiff": "tiff",
}

# Bound in main() before the server accepts a connection, so every handler
# sees a loaded model. Declared here rather than as a class attribute so the
# type is a plain ModelRunner instead of an Optional every call site must
# narrow.
RUNNER: "ModelRunner"


class ModelRunner:
    """Owns the loaded model. Every method runs on the serving thread."""

    def __init__(self, model_path: str, trust_remote_code: bool, default_max_tokens: int):
        from mlx_vlm import load

        self.model_path = model_path
        self.default_max_tokens = default_max_tokens
        kwargs = {"trust_remote_code": True} if trust_remote_code else {}
        self.model, self.processor = load(model_path, **kwargs)

    def generate(self, prompt: str, image_paths: list[str], max_tokens: int, temperature: float) -> str:
        from mlx_vlm import generate
        from mlx_vlm.prompt_utils import apply_chat_template

        formatted = apply_chat_template(
            self.processor,
            self.model.config,
            prompt,
            num_images=len(image_paths),
        )
        result = generate(
            model=self.model,
            processor=self.processor,
            prompt=formatted,
            image=image_paths or None,
            max_tokens=max_tokens,
            temperature=temperature,
            verbose=False,
        )
        # mlx-vlm returns a GenerationResult; older paths returned a bare str.
        return getattr(result, "text", result)


def materialize_image(url: str, tmpdir: str, index: int) -> str:
    """Write an OpenAI image_url data: payload to a file and return its path.

    DATA URIs ONLY, BY DESIGN. The OpenAI schema also allows an http(s) URL,
    and honouring it would hand any caller a request primitive originating
    from inside the serving host — a server-side request forgery reaching
    internal services the caller cannot address directly. Nothing here needs
    it: callers already hold the page bytes and send them inline. A bare
    filesystem path is refused for the mirror-image reason, since resolving it
    would read any file the worker can reach.
    """
    match = DATA_URI.match(url)
    if not match:
        raise ValueError("image_url must be a data: URI carrying base64 image bytes")

    raw = base64.b64decode(match.group("payload"))
    # Map through a fixed table rather than using the declared subtype
    # directly: the mime is caller-supplied, and letting it reach a filename
    # puts a user-controlled component in a path. The extension is cosmetic
    # anyway — PIL sniffs the real format from the bytes — so an unrecognised
    # subtype falls back rather than failing the request.
    suffix = SUFFIX_BY_MIME_SUBTYPE.get(match.group("mime").split("/")[-1].lower(), "png")

    path = os.path.join(tmpdir, f"image-{index}.{suffix}")
    with open(path, "wb") as handle:
        handle.write(raw)
    return path


def parse_messages(messages: list) -> tuple[str, list[str], list[str]]:
    """Flatten OpenAI messages into (prompt_text, image_urls, system_texts)."""
    texts: list[str] = []
    images: list[str] = []
    systems: list[str] = []

    for message in messages:
        role = message.get("role", "user")
        content = message.get("content")
        if isinstance(content, str):
            (systems if role == "system" else texts).append(content)
            continue
        for part in content or []:
            kind = part.get("type")
            if kind == "text":
                (systems if role == "system" else texts).append(part.get("text", ""))
            elif kind == "image_url":
                url = (part.get("image_url") or {}).get("url", "")
                if url:
                    images.append(url)

    return "\n".join(t for t in texts if t), images, systems


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    @property
    def runner(self) -> ModelRunner:
        return RUNNER

    def log_message(self, format, *args):  # noqa: A002 - name fixed by the base class
        # Route through stderr explicitly and flush per line so launchd
        # captures request logs in order with the startup lines above.
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))
        sys.stderr.flush()

    def _send(self, code: int, payload: dict):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/") in ("/health", "/healthz"):
            self._send(200, {"status": "ok", "model": self.runner.model_path})
        elif self.path.rstrip("/") == "/v1/models":
            self._send(
                200,
                {
                    "object": "list",
                    "data": [
                        {
                            "id": self.runner.model_path,
                            "object": "model",
                            "created": int(time.time()),
                            "owned_by": "mlx-vlm-adapter",
                        }
                    ],
                },
            )
        else:
            self._send(404, {"error": {"message": "not found", "type": "invalid_request_error"}})

    def do_POST(self):
        if self.path.rstrip("/") != "/v1/chat/completions":
            self._send(404, {"error": {"message": "not found", "type": "invalid_request_error"}})
            return

        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY_BYTES:
            self._send(413, {"error": {"message": "missing or oversized body", "type": "invalid_request_error"}})
            return

        try:
            payload = json.loads(self.rfile.read(length))
        except (ValueError, UnicodeDecodeError) as exc:
            self._send(400, {"error": {"message": f"invalid JSON body: {exc}", "type": "invalid_request_error"}})
            return

        if payload.get("stream"):
            self._send(
                400,
                {"error": {"message": "streaming is not supported by this adapter", "type": "invalid_request_error"}},
            )
            return

        prompt, image_urls, systems = parse_messages(payload.get("messages") or [])
        if systems:
            prompt = "\n".join(systems + ([prompt] if prompt else []))

        max_tokens = int(payload.get("max_tokens") or self.runner.default_max_tokens)
        temperature = float(payload.get("temperature") or 0.0)

        started = time.time()
        try:
            with tempfile.TemporaryDirectory(prefix="mlx-vlm-adapter-") as tmpdir:
                try:
                    paths = [materialize_image(u, tmpdir, i) for i, u in enumerate(image_urls)]
                except (ValueError, OSError) as exc:
                    # A rejected or unfetchable image is the caller's mistake,
                    # not a server fault. Returning 500 here made a bad request
                    # look like an outage to anything with retry logic.
                    self._send(400, {"error": {"message": f"invalid image: {exc}", "type": "invalid_request_error"}})
                    return
                text = self.runner.generate(prompt, paths, max_tokens, temperature)
        except Exception as exc:  # surfaced to the caller, never swallowed
            self.log_message("generation failed: %r", exc)
            self._send(500, {"error": {"message": f"generation failed: {exc}", "type": "server_error"}})
            return

        self._send(
            200,
            {
                "id": f"chatcmpl-{int(started * 1000)}",
                "object": "chat.completion",
                "created": int(started),
                "model": self.runner.model_path,
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": text},
                        "finish_reason": "stop",
                    }
                ],
            },
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="OpenAI-compatible mlx-vlm adapter (single model, serialized).")
    parser.add_argument("--model", required=True, help="Hugging Face repo id or local path.")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--trust-remote-code", action="store_true")
    parser.add_argument("--max-tokens", type=int, default=4096, help="Default when a request omits max_tokens.")
    args = parser.parse_args()

    global RUNNER
    sys.stderr.write(f"mlx-vlm-adapter: loading {args.model}\n")
    sys.stderr.flush()
    RUNNER = ModelRunner(args.model, args.trust_remote_code, args.max_tokens)

    # HTTPServer, not ThreadingHTTPServer: one request at a time on the main
    # thread is the entire point (see module docstring).
    server = HTTPServer((args.host, args.port), Handler)
    sys.stderr.write(f"mlx-vlm-adapter: serving {args.model} on {args.host}:{args.port}\n")
    sys.stderr.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
