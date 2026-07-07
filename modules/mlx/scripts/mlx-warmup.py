#!/usr/bin/env python3
# /// script
# dependencies = []
# ///
"""Warm the declared MLX preload list after the proxy comes up.

The LaunchAgent waits for the loopback API to answer, then sends a 1-token
chat completion to each preloaded model. That forces the weights to fault in
at boot instead of on the first user request.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

TRANSIENT_HTTP_CODES = {408, 429, 500, 502, 503, 504}


def parse_models() -> list[str]:
    """Load the preload list from env, preserving the Nix order."""
    raw_json = os.environ.get("MLX_PRELOAD_MODELS_JSON")
    if raw_json:
        try:
            models = json.loads(raw_json)
        except json.JSONDecodeError as exc:
            raise SystemExit(
                f"ERROR: MLX_PRELOAD_MODELS_JSON is not valid JSON: {exc}"
            ) from exc
    else:
        raw = os.environ.get("MLX_PRELOAD_MODELS", "").strip()
        models = raw.split() if raw else []

    if not isinstance(models, list):
        raise SystemExit("ERROR: preload models must be a JSON list or space-separated list")

    cleaned = [model.strip() for model in models if isinstance(model, str) and model.strip()]
    # Preserve order while removing duplicates.
    return list(dict.fromkeys(cleaned))


def request_json(url: str, payload: dict[str, object], timeout: int) -> dict[str, object]:
    """POST JSON and return the decoded response."""
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        raw = response.read()
    if not raw:
        return {}
    decoded = json.loads(raw.decode("utf-8"))
    if not isinstance(decoded, dict):
        raise RuntimeError(f"Unexpected non-object response from {url}")
    return decoded


def wait_for_api(models_url: str, deadline: float) -> None:
    """Poll the proxy until /models answers successfully."""
    while True:
        try:
            with urllib.request.urlopen(models_url, timeout=10) as response:
                if response.status == 200:
                    return
        except Exception:
            pass

        if time.monotonic() >= deadline:
            raise TimeoutError(f"Timed out waiting for {models_url}")
        time.sleep(2)


def warm_model(api_url: str, model: str, deadline: float) -> None:
    """Send a 1-token completion to fault a model into memory."""
    chat_url = f"{api_url.rstrip('/')}/chat/completions"
    payload = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": "warmup",
            }
        ],
        "max_tokens": 1,
        "stream": False,
        "temperature": 0,
    }
    last_error: Exception | None = None

    while True:
        try:
            response = request_json(chat_url, payload, timeout=20)
            if "error" in response:
                raise RuntimeError(f"{model}: {response['error']}")
            return
        except urllib.error.HTTPError as exc:
            if exc.code not in TRANSIENT_HTTP_CODES:
                raise RuntimeError(f"{model}: HTTP {exc.code}") from exc
            last_error = exc
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as exc:
            last_error = exc
        except RuntimeError:
            raise

        if time.monotonic() >= deadline:
            if last_error is not None:
                raise TimeoutError(f"{model}: timed out after repeated failures: {last_error}") from last_error
            raise TimeoutError(f"{model}: timed out after repeated failures")
        time.sleep(2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Warm preloaded MLX models")
    parser.add_argument(
        "--timeout",
        type=int,
        default=900,
        help="Maximum time to wait for the proxy and warmup requests (seconds)",
    )
    args = parser.parse_args()

    api_url = os.environ.get("MLX_API_URL")
    if not api_url:
        print("ERROR: MLX_API_URL not set", file=sys.stderr)
        return 1

    models = parse_models()
    if not models:
        print("No preload models configured; nothing to warm.")
        return 0

    deadline = time.monotonic() + args.timeout
    models_url = f"{api_url.rstrip('/')}/models"

    print(f"Waiting for MLX API at {api_url} ...")
    wait_for_api(models_url, deadline)
    print(f"API ready; warming {len(models)} model(s): {', '.join(models)}")

    for model in models:
        model_start = time.monotonic()
        warm_model(api_url, model, deadline)
        elapsed = time.monotonic() - model_start
        print(f"Warmed {model} in {elapsed:.1f}s")

    print("MLX warmup completed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
