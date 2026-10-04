import sys
import unittest
from pathlib import Path
from queue import Queue

sys.path.insert(0, str(Path(__file__).parents[1] / "modules/mlx/scripts"))
from mlx_bounded_queue import DropOldestRequestQueue, RequestEvictedError


class DropOldestRequestQueueTest(unittest.TestCase):
    def test_full_queue_refuses_oldest_pending_request(self):
        pending = DropOldestRequestQueue(maxsize=25)
        active_response = Queue()
        pending.put((active_response, "already-decoding", {}))
        active = pending.get_nowait()

        response_queues = []
        for index in range(25):
            response_queue = Queue()
            response_queues.append(response_queue)
            pending.put((response_queue, index, {}))

        newest_response = Queue()
        pending.put((newest_response, 25, {}))

        evicted = response_queues[0].get_nowait()
        self.assertIsInstance(evicted, RequestEvictedError)
        self.assertIn("pending queue was full", str(evicted))
        self.assertEqual([pending.get_nowait()[1] for _ in range(25)], list(range(1, 26)))
        self.assertEqual(active[1], "already-decoding")
        self.assertTrue(active_response.empty())
        self.assertTrue(newest_response.empty())


if __name__ == "__main__":
    unittest.main()
