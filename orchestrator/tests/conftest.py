"""Shared environment for tests that exercise host-configured model defaults."""

import os

os.environ["MLX_API_URL"] = "https://router.example.invalid/v1"
os.environ["MLX_DEFAULT_MODEL"] = "test-model"
