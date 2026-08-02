#!/usr/bin/env python3
# /// script
# dependencies = []
# ///
"""Warm the declared MLX preload list after the proxy comes up.

The LaunchAgent waits for the loopback API to answer, then sends a 1-token
chat completion to each preloaded model. That forces the weights to fault in
at boot instead of on the first user request.

RESTART BOUND (the livelock fix): the LaunchAgent's KeepAlive.SuccessfulExit
= false restarts this process on ANY nonzero exit, with no ceiling of its
own — under sustained host churn a cycle can legitimately run out its whole
deadline, exit 1, get restarted, and immediately re-acquire the model's
llama-swap concurrency slot to try again, forever. Warmup is a preload
optimisation, not required for serving (a cold model still answers the first
real request, just slower), so past MAX_CONSECUTIVE_FAILURES full-cycle
failures in a row this gives up on purpose: it exits 0, which
KeepAlive.SuccessfulExit=false reads as "do not restart", permanently ending
the loop until the next legitimate trigger (RunAtLoad on the next
reboot/login, or an explicit kickstart after a real proxy restart). The
streak is tracked in FAIL_MARKER — a plain integer file, one process's
memory does not survive its own restart — mirroring mlx-watchdog.sh's own
fail_marker/read_int convention so there is one established pattern for
"bounded consecutive failures" in this module, not two.

RE-INVOCATION BOUND (the kickstart-bypass gap): the restart bound above only
covers launchd's OWN KeepAlive restarts, which are paced by the LaunchAgent's
ThrottleInterval. `launchctl kickstart -k` is a SEPARATE trigger that exists
specifically to force an immediate (re)start regardless of throttle state, and
this process is kickstarted that way by more than just launchd itself — e.g.
modules/mlx/scripts/cluster-link-helpers.sh's restore_normal_serving() and
mlx-default.sh both do it. A caller that retries a failing operation in a
tight loop and calls restore_normal_serving() on every attempt (observed:
cluster-link-watcher.sh's peer-rendezvous-absent standdown, which has no cap
of its own on that path) re-triggers a full warm cycle every time, and every
cycle — successful or not — holds the preloaded model's llama-swap
concurrency slot for as long as the warm takes. MIN_INTERVAL_SECONDS bounds
how often this process will actually attempt a warm, independent of exit
status and independent of who is asking, mirroring ThrottleInterval's own
value (modules/mlx/launchd.nix) so there is one source of truth. A caller
that needs the model sooner still gets it: llama-swap loads any named model
on demand for a real request regardless of whether this background job ran.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

TRANSIENT_HTTP_CODES = {408, 429, 500, 502, 503, 504}

# Fallback deadline when MLX_WARMUP_TIMEOUT_SECONDS is unset (e.g. a manual,
# non-Nix invocation): the single-model worst case Nix derives this from
# (programs.mlx.proxy.healthCheckTimeout, 180s — "70GB models take 20-60s to
# load") plus margin for the completion request and the proxy-readiness poll.
# The Nix-provided value is the real one and scales with how many models this
# host actually preloads; see modules/mlx/default.nix's warmupTimeoutSeconds.
DEFAULT_TIMEOUT_SECONDS = 240
# Give up after this many consecutive full-cycle failures rather than restart
# forever — the actual livelock fix; see the module docstring above.
MAX_CONSECUTIVE_FAILURES = 3
FAIL_MARKER = Path(
    os.environ.get(
        "MLX_WARMUP_FAIL_MARKER",
        str(Path.home() / "Library/Caches/mlx-model-server/warmup-failures"),
    )
)
# Fallback cooldown when MLX_WARMUP_MIN_INTERVAL_SECONDS is unset: matches the
# ThrottleInterval default on the LaunchAgent (modules/mlx/launchd.nix) so a
# manual/non-Nix run behaves like the deployed one. See the module docstring's
# RE-INVOCATION BOUND section for why this exists separately from
# MAX_CONSECUTIVE_FAILURES.
DEFAULT_MIN_INTERVAL_SECONDS = 120
LAST_ATTEMPT_MARKER = Path(
    os.environ.get(
        "MLX_WARMUP_LAST_ATTEMPT_MARKER",
        str(Path.home() / "Library/Caches/mlx-model-server/warmup-last-attempt"),
    )
)


def read_int(path: Path) -> int:
    """Missing/corrupt marker coerces to 0 (mirrors mlx-watchdog.sh's read_int)."""
    try:
        return max(0, int(path.read_text().strip()))
    except (OSError, ValueError):
        return 0


def clear_failure_streak() -> None:
    FAIL_MARKER.unlink(missing_ok=True)


def seconds_since_last_attempt() -> float | None:
    """None means "no recorded attempt" (first run, or a corrupt marker) —
    treated as "cooldown already elapsed" by the caller."""
    try:
        return time.time() - float(LAST_ATTEMPT_MARKER.read_text().strip())
    except (OSError, ValueError):
        return None


def record_attempt_start() -> None:
    """Stamped right before this process actually tries to reach the API —
    not on a skip — so a min-interval violation is measured start-to-start
    regardless of how the previous attempt ended."""
    LAST_ATTEMPT_MARKER.parent.mkdir(parents=True, exist_ok=True)
    LAST_ATTEMPT_MARKER.write_text(f"{time.time()}\n")


def record_cycle_failure(reason: str, max_consecutive: int) -> int:
    """One full warmup cycle failed. Bump the streak and return the exit code:
    1 while there is budget left (KeepAlive restarts, another bounded try),
    0 once the streak is exhausted (a deliberate give-up, not a success —
    KeepAlive.SuccessfulExit=false stops restarting on exit 0)."""
    FAIL_MARKER.parent.mkdir(parents=True, exist_ok=True)
    streak = read_int(FAIL_MARKER) + 1
    FAIL_MARKER.write_text(f"{streak}\n")

    if streak < max_consecutive:
        print(f"WARMUP FAILED ({streak}/{max_consecutive} consecutive): {reason}", file=sys.stderr)
        return 1

    print(
        f"WARMUP GIVING UP after {streak} consecutive failed cycles: {reason}\n"
        "Not required for serving - a cold model still answers the first real "
        "request, just slower. No further automatic retries until the next "
        "reboot/login or an explicit restart.",
        file=sys.stderr,
    )
    # A give-up is a resolved outcome, not an ongoing one: the next legitimate
    # trigger deserves its own fresh budget rather than starting pre-exhausted.
    clear_failure_streak()
    # CAVEAT for anything that ever reads this process's exit status directly
    # (not just launchd): 0 here does NOT mean warmup succeeded, only that it
    # stopped trying. Something wiring monitoring to "warmup exited 0 ->
    # healthy" would misread a give-up as a good outcome; the loud stderr
    # lines above are what actually distinguishes the two.
    return 0


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
            # Reaching here means the try/except above ran at least once and
            # took one of the two `last_error = exc` branches (the only ways
            # to fall through without returning or raising), so last_error is
            # always set at this point.
            raise TimeoutError(f"{model}: timed out after repeated failures: {last_error}") from last_error
        time.sleep(2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Warm preloaded MLX models")
    parser.add_argument(
        "--timeout",
        type=int,
        default=int(os.environ.get("MLX_WARMUP_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS)),
        help="Maximum time to wait for the proxy and warmup requests (seconds)",
    )
    parser.add_argument(
        "--max-consecutive-failures",
        type=int,
        default=int(os.environ.get("MLX_WARMUP_MAX_CONSECUTIVE_FAILURES", MAX_CONSECUTIVE_FAILURES)),
        help="Give up (exit 0, stop restarting) after this many consecutive full-cycle failures",
    )
    parser.add_argument(
        "--min-interval",
        type=int,
        default=int(os.environ.get("MLX_WARMUP_MIN_INTERVAL_SECONDS", DEFAULT_MIN_INTERVAL_SECONDS)),
        help="Minimum seconds between warm attempts, regardless of trigger or outcome (see RE-INVOCATION BOUND)",
    )
    args = parser.parse_args()

    api_url = os.environ.get("MLX_API_URL")
    if not api_url:
        print("ERROR: MLX_API_URL not set", file=sys.stderr)
        return 1

    models = parse_models()
    if not models:
        print("No preload models configured; nothing to warm.")
        clear_failure_streak()
        return 0

    since_last = seconds_since_last_attempt()
    if since_last is not None and since_last < args.min_interval:
        print(
            f"Skipping warm attempt: the last one started {since_last:.1f}s ago, "
            f"under the {args.min_interval}s minimum interval. Not a failure — a "
            "real request to a preloaded model still loads it on demand; this "
            "only bounds how often this background job re-acquires the "
            "concurrency slot when something kickstarts it repeatedly."
        )
        return 0
    record_attempt_start()

    deadline = time.monotonic() + args.timeout
    models_url = f"{api_url.rstrip('/')}/models"

    try:
        print(f"Waiting for MLX API at {api_url} ...")
        wait_for_api(models_url, deadline)
        print(f"API ready; warming {len(models)} model(s): {', '.join(models)}")

        for model in models:
            model_start = time.monotonic()
            warm_model(api_url, model, deadline)
            elapsed = time.monotonic() - model_start
            print(f"Warmed {model} in {elapsed:.1f}s")
    except TimeoutError as exc:
        # The one and only failure mode both wait_for_api and warm_model raise
        # (see their docstrings) — anything else is a real bug and should
        # propagate with a traceback, not get silently folded into the streak.
        return record_cycle_failure(str(exc), args.max_consecutive_failures)

    print("MLX warmup completed.")
    clear_failure_streak()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
