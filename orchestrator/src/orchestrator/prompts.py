"""Load canonical Dryvist prompt resources from the Nix-injected catalog."""

from __future__ import annotations

import os
from pathlib import Path

PROMPT_DIR_ENV = "NIX_AI_PROMPT_DIR"
RESOURCE_PREFIX = "prompt://dryvist/applications/"


def strip_okf_frontmatter(content: str) -> str:
    """Return a prompt body after removing its required OKF frontmatter."""
    if not content.startswith("---\n"):
        msg = "Prompt asset is missing OKF frontmatter"
        raise ValueError(msg)

    parts = content.split("---\n", 2)
    if len(parts) != 3 or not parts[1].strip():
        msg = "Prompt asset has malformed OKF frontmatter"
        raise ValueError(msg)
    return parts[2].rstrip("\n")


def load_prompt_resource(resource: str) -> str:
    """Resolve an applications prompt resource from ``NIX_AI_PROMPT_DIR``."""
    if not resource.startswith(RESOURCE_PREFIX):
        msg = f"Unsupported prompt resource: {resource}"
        raise ValueError(msg)

    resource_name = resource.removeprefix(RESOURCE_PREFIX)
    if not resource_name or "/" in resource_name or resource_name in {".", ".."}:
        msg = f"Invalid prompt resource: {resource}"
        raise ValueError(msg)

    prompt_dir = os.environ.get(PROMPT_DIR_ENV)
    if not prompt_dir:
        msg = f"{PROMPT_DIR_ENV} is not set; enter the nix-ai Nix dev shell"
        raise RuntimeError(msg)

    prompt_path = Path(prompt_dir) / f"{resource_name}.md"
    try:
        content = prompt_path.read_text()
    except FileNotFoundError:
        msg = f"Prompt resource not found: {resource} ({prompt_path})"
        raise FileNotFoundError(msg) from None
    return strip_okf_frontmatter(content)
