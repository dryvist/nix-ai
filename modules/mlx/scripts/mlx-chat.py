"""mlx-chat — Multi-turn chat against the local MLX inference server."""

import json
import os
import sys
import urllib.request

from openai import OpenAI

API_URL = os.environ.get("MLX_API_URL", "http://127.0.0.1:11434/v1")


def resolution_note(requested, running):
    """Return a line naming the REQUESTED model and the one actually loaded.

    The response body cannot be used for this. When llama-swap substituted a
    model it echoed the REQUESTED name back in `response.model` with a 200, so
    a client comparing against that field compares against the value that lied
    — which is why benchmark throughput for one model was published under two
    other models' names. llama-swap's /running endpoint reports the physical
    model it actually has loaded, so it is the one side of the comparison the
    substitution could not forge.

    `running` is the parsed /running payload. Returns None when the two agree,
    or when nothing is loaded yet (a cold proxy is not a substitution).

    Best-effort audit signal, NOT a guarantee: a multi-resident host lists
    several models, and the model can swap between the request and this probe.
    It makes a substitution visible; it does not make one impossible. The
    structural guarantee is that an unserved name now 404s.
    """
    loaded = [m.get("model") for m in (running or {}).get("running", []) if m.get("model")]
    if not loaded or requested in loaded:
        return None
    return f"requested={requested!r} but llama-swap has loaded {loaded!r}"


def log_resolution(requested):
    """Print the requested-vs-loaded resolution to stderr. Never fatal."""
    try:
        root = API_URL.split("/v1")[0]
        with urllib.request.urlopen(f"{root}/running", timeout=2) as resp:  # noqa: S310
            note = resolution_note(requested, json.load(resp))
    except Exception:
        return  # the probe is an audit aid; it must never break the chat
    if note:
        print(f"mlx-chat: MODEL SUBSTITUTION: {note}", file=sys.stderr)


client = OpenAI(base_url=API_URL, api_key="n/a")
model = os.environ["MLX_DEFAULT_MODEL"]
messages = []

# One-shot from stdin
if not sys.stdin.isatty():
    messages.append({"role": "user", "content": sys.stdin.read().strip()})
    out = client.chat.completions.create(model=model, messages=messages).choices[0].message.content
    log_resolution(model)
    print(out)
    sys.exit(0)

# Seed from args
if len(sys.argv) > 1:
    prompt = " ".join(sys.argv[1:])
    messages.append({"role": "user", "content": prompt})
    r = client.chat.completions.create(model=model, messages=messages)
    log_resolution(model)
    print(f"MLX: {r.choices[0].message.content}\n")
    messages.append({"role": "assistant", "content": r.choices[0].message.content})

# Interactive loop
while True:
    try:
        user = input("You: ").strip()
    except (EOFError, KeyboardInterrupt):
        break
    if not user or user in ("exit", "quit"):
        break
    messages.append({"role": "user", "content": user})
    r = client.chat.completions.create(model=model, messages=messages)
    log_resolution(model)
    print(f"MLX: {r.choices[0].message.content}\n")
    messages.append({"role": "assistant", "content": r.choices[0].message.content})
