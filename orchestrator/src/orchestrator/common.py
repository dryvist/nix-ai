"""Shared utilities for the orchestrator."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import numpy as np
import yaml


def local_router_url() -> str:
    """Return the local API URL exported by the host AI-stack configuration."""
    endpoint = os.environ.get("MLX_API_URL")
    if not endpoint:
        msg = "MLX_API_URL is unset; configure it from services.aiStack.localRouterUrl."
        raise RuntimeError(msg)
    return endpoint


def load_yaml_file(path: str | Path) -> dict[str, Any]:
    """Load and return parsed YAML from a file.

    Raises:
        FileNotFoundError: If the file does not exist.
        ValueError: If the parsed YAML is not a mapping (e.g. empty file, list, scalar).
    """
    path = Path(path)
    try:
        with path.open() as fh:
            data = yaml.safe_load(fh)
    except FileNotFoundError:
        msg = f"File not found: {path}"
        raise FileNotFoundError(msg) from None
    if not isinstance(data, dict):
        msg = f"Expected a YAML mapping in {path}, got {type(data).__name__}"
        raise ValueError(msg)
    return data


def l2_normalize(arr: np.ndarray) -> np.ndarray:
    """L2-normalize an array of vectors (row-wise)."""
    norms = np.linalg.norm(arr, axis=1, keepdims=True) + 1e-10
    return arr / norms
