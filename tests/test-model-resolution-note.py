#!/usr/bin/env python3
"""Unit test for mlx-chat's requested-vs-loaded resolution note.

The case that matters is the one that actually happened: a request naming
gpt-oss-120b answered by Qwen3-Coder-30B's weights, 200 OK, with the REQUESTED
name echoed back in the response body. Any check reading `response.model` would
have compared against the forged value and stayed silent. This note reads
llama-swap's /running instead, which reports the model really loaded.

Run: python3 tests/test-model-resolution-note.py
"""

import pathlib
import sys
import types

# mlx-chat.py opens a client and reads MLX_DEFAULT_MODEL at import time, so only
# the prefix above that line is executed — which is why the helper is a pure
# function taking the /running payload rather than fetching it itself.
#
# `openai` is stubbed rather than required: this test asserts a pure string
# comparison and must run under the plain interpreter in `nix flake check`,
# where the chat client's third-party dependency is not present.
_openai_stub = types.ModuleType("openai")
_openai_stub.OpenAI = object  # type: ignore[attr-defined]
sys.modules.setdefault("openai", _openai_stub)

SRC = pathlib.Path(__file__).resolve().parent.parent / "modules/mlx/scripts/mlx-chat.py"
lines = SRC.read_text().split("\n")
cut = next(i for i, line in enumerate(lines) if line.startswith("client = OpenAI("))
namespace: dict = {}
exec("\n".join(lines[:cut]), namespace)  # noqa: S102
resolution_note = namespace["resolution_note"]

FAILURES = []


def check(label, got, want):
    if got != want:
        FAILURES.append(f"{label}: got {got!r}, want {want!r}")


# The real incident: requested one model, a different one is loaded.
check(
    "substitution is reported",
    resolution_note(
        "mlx-community/gpt-oss-120b",
        {"running": [{"model": "mlx-community/Qwen3-Coder-30B"}]},
    ),
    "requested='mlx-community/gpt-oss-120b' but llama-swap has loaded "
    "['mlx-community/Qwen3-Coder-30B']",
)

# Agreement is silent.
check(
    "match is silent",
    resolution_note(
        "mlx-community/gpt-oss-120b",
        {"running": [{"model": "mlx-community/gpt-oss-120b"}]},
    ),
    None,
)

# A multi-resident host that HAS the requested model loaded is not a substitution.
check(
    "multi-resident containing the request is silent",
    resolution_note(
        "mlx-community/gpt-oss-120b",
        {
            "running": [
                {"model": "mlx-community/Qwen3-Coder-30B"},
                {"model": "mlx-community/gpt-oss-120b"},
            ]
        },
    ),
    None,
)

# A cold proxy has nothing loaded — absence of a model is not a substitution.
check("cold proxy is silent", resolution_note("mlx-community/gpt-oss-120b", {"running": []}), None)
check("empty payload is silent", resolution_note("mlx-community/gpt-oss-120b", {}), None)

if FAILURES:
    for f in FAILURES:
        print(f"FAIL {f}", file=sys.stderr)
    sys.exit(1)
print("ok - resolution note reports substitution and stays silent otherwise")
