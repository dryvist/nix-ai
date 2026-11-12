import io
import sys
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1] / "modules/mlx/scripts"))
from mlx_generation_watchdog import (
    CHECK_INTERVAL_SECONDS,
    EXIT_GENERATION_DEAD,
    model_name_from_argv,
    start_generation_watchdog,
    watch_generation,
)

TOKEN_LINE = "MLX_GENERATION_DEAD model=fake/model reason=generation thread not alive\n"


class FakeGeneration:
    """A generation thread that stays alive until kill(), liveness read as mlx_lm does."""

    def __init__(self):
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._stop.wait, daemon=True)
        self._thread.start()

    def generation_available(self):
        return self._thread.is_alive()

    def kill(self):
        self._stop.set()
        self._thread.join(5)


class StopWatch(Exception):
    pass


class Scripted:
    """Liveness answers in order; raises StopWatch once they run out."""

    def __init__(self, answers):
        self._answers = list(answers)
        self.checks = 0

    def __call__(self):
        if not self._answers:
            raise StopWatch()
        self.checks += 1
        return self._answers.pop(0)


class GenerationWatchdogTest(unittest.TestCase):
    def test_dead_thread_exits_70_after_two_checks_with_one_token_line(self):
        generation = FakeGeneration()
        generation.kill()
        sleeps, exits, err = [], [], io.StringIO()

        watch_generation(
            generation.generation_available,
            "fake/model",
            sleep=sleeps.append,
            exit_process=exits.append,
            err=err,
        )

        self.assertEqual(exits, [EXIT_GENERATION_DEAD])
        self.assertEqual(sleeps, [CHECK_INTERVAL_SECONDS] * 2)
        self.assertEqual(err.getvalue(), TOKEN_LINE)

    def test_thread_dying_while_watched_exits_from_daemon_thread(self):
        generation = FakeGeneration()
        exited = threading.Event()
        exits, err = [], io.StringIO()

        def record(code):
            exits.append(code)
            exited.set()

        start_generation_watchdog(
            generation.generation_available,
            "fake/model",
            interval=0.01,
            exit_process=record,
            err=err,
        )
        generation.kill()

        self.assertTrue(exited.wait(5), "watchdog did not exit after the thread died")
        self.assertEqual(exits, [EXIT_GENERATION_DEAD])
        self.assertEqual(err.getvalue(), TOKEN_LINE)

    def test_live_thread_never_exits(self):
        generation = FakeGeneration()
        exits, err = [], io.StringIO()
        checks = Scripted([True] * 5)

        def live_check():
            return checks() and generation.generation_available()

        try:
            with self.assertRaises(StopWatch):
                watch_generation(
                    live_check,
                    "fake/model",
                    sleep=lambda seconds: None,
                    exit_process=exits.append,
                    err=err,
                )
            self.assertEqual(checks.checks, 5)
            self.assertEqual(exits, [])
            self.assertEqual(err.getvalue(), "")
        finally:
            generation.kill()

    def test_single_transient_false_does_not_exit(self):
        exits, err = [], io.StringIO()
        checks = Scripted([True, False, True, False, True])

        with self.assertRaises(StopWatch):
            watch_generation(
                checks,
                "fake/model",
                sleep=lambda seconds: None,
                exit_process=exits.append,
                err=err,
            )

        self.assertEqual(checks.checks, 5)
        self.assertEqual(exits, [])
        self.assertEqual(err.getvalue(), "")

    def test_two_misses_in_a_row_after_a_recovery_exit_on_the_second(self):
        exits, err = [], io.StringIO()
        checks = Scripted([False, True, False, False, False])

        watch_generation(
            checks,
            "fake/model",
            sleep=lambda seconds: None,
            exit_process=exits.append,
            err=err,
        )

        self.assertEqual(checks.checks, 4)
        self.assertEqual(exits, [EXIT_GENERATION_DEAD])
        self.assertEqual(err.getvalue(), TOKEN_LINE)

    def test_model_name_comes_from_the_model_argument(self):
        self.assertEqual(
            model_name_from_argv(["launch.py", "--model", "org/model", "--port", "1"]),
            "org/model",
        )
        self.assertEqual(model_name_from_argv(["launch.py", "--model=org/model"]), "org/model")
        self.assertEqual(model_name_from_argv(["launch.py"]), "unknown")


if __name__ == "__main__":
    unittest.main()
