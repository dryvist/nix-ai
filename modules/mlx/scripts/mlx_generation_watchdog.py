# Exit the model server when its generation thread dies, so launchd restarts it.
#
# mlx_lm.server keeps its HTTP listener up after the generation thread dies:
# GET /v1/models still answers 200 while every completion fails with
# "generation thread died", and the process never exits, so launchd KeepAlive
# never fires. This watchdog polls the generator's own liveness predicate and
# exits with EXIT_GENERATION_DEAD (non-zero), which KeepAlive restarts.
#
# Upstream's GET /health returns 503 when the generation thread is dead
# (mlx_lm/server.py handle_health_check), so an external probe should use it.

import os
import sys
import threading
import time

EXIT_GENERATION_DEAD = 70
CHECK_INTERVAL_SECONDS = 10
FAILURE_THRESHOLD = 2
TOKEN = "MLX_GENERATION_DEAD"


def model_name_from_argv(argv):
    for index, arg in enumerate(argv):
        if arg == "--model" and index + 1 < len(argv):
            return argv[index + 1]
        if arg.startswith("--model="):
            return arg.split("=", 1)[1]
    return "unknown"


def watch_generation(
    is_available,
    model,
    interval=CHECK_INTERVAL_SECONDS,
    threshold=FAILURE_THRESHOLD,
    sleep=time.sleep,
    exit_process=os._exit,
    err=None,
):
    """Check is_available every interval seconds until it is false threshold
    checks in a row, then log the token line and call exit_process once."""
    misses = 0
    while True:
        sleep(interval)
        if is_available():
            misses = 0
            continue
        misses += 1
        if misses < threshold:
            continue
        print(
            f"{TOKEN} model={model} reason=generation thread not alive",
            file=err if err is not None else sys.stderr,
            flush=True,
        )
        exit_process(EXIT_GENERATION_DEAD)
        return


def start_generation_watchdog(is_available, model, **options):
    """Run watch_generation on a daemon thread so it never keeps the process alive."""
    thread = threading.Thread(
        target=watch_generation,
        args=(is_available, model),
        kwargs=options,
        name="mlx-generation-watchdog",
        daemon=True,
    )
    thread.start()
    return thread
