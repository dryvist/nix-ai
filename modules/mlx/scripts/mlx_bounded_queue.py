"""Bound the pinned mlx-lm request queue by evicting its oldest waiter."""

from queue import Queue


class RequestEvictedError(RuntimeError):
    """The request was still pending when a newer request took its slot."""


class DropOldestRequestQueue(Queue):
    """An mlx-lm request queue that never rejects the newest arrival."""

    def __init__(self, maxsize: int):
        if maxsize < 1:
            raise ValueError("maxsize must be positive")
        super().__init__(maxsize=maxsize)

    def put(self, item, block=True, timeout=None):
        del block, timeout  # A full queue is handled by replacing its oldest waiter.
        if not isinstance(item, tuple) or len(item) != 3 or not hasattr(item[0], "put"):
            raise TypeError("mlx-lm pending queue item shape changed")

        with self.not_full:
            if self._qsize() >= self.maxsize:
                oldest = self._get()
                oldest[0].put(
                    RequestEvictedError(
                        "Request evicted: the per-model pending queue was full; "
                        "a newer request took its place."
                    )
                )
                self.unfinished_tasks -= 1
                if self.unfinished_tasks == 0:
                    self.all_tasks_done.notify_all()
                self.not_full.notify()

            self._put(item)
            self.unfinished_tasks += 1
            self.not_empty.notify()
