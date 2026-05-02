#!/usr/bin/env python3
# /// script
# dependencies = []
# ///
"""Auto-discover downloaded MLX models and register them with llama-swap.

Scans the HuggingFace cache for downloaded models, merges them into the
llama-swap runtime config, and writes the result to the mutable config path.
llama-swap's --watch-config flag auto-reloads when the file changes.

Usage:
  mlx-discover            # Discover and register all fitting models
  mlx-discover --quiet    # Suppress informational output
  mlx-discover --dry-run  # Show what would be registered without writing
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

EXCLUDE_PATTERN = re.compile(
    r"(whisper|FLUX|Embedding|embedding|TTS|tts|OCR|ocr|CLIP|clip|siglip|bert|bge-|e5-|gte-|nomic-embed|jina-embed)",
    re.IGNORECASE,
)


def get_memory_budget_gb() -> int:
    """Return available memory in GB (total - 20 GB reserved for system)."""
    sysctl = shutil.which("sysctl") or "/usr/sbin/sysctl"
    result = subprocess.run(
        [sysctl, "-n", "hw.memsize"], capture_output=True, text=True, check=True
    )
    total_bytes = int(result.stdout.strip())
    total_gb = total_bytes // (1024**3)
    return total_gb - 20


def dir_size_gb(path: Path) -> float:
    """Return directory size in GB.

    HuggingFace cache layout stores real files under ``blobs/`` and exposes
    them through ``snapshots/<revision>/`` trees of symlinks pointing back to
    those blobs. A naive ``rglob`` + ``stat`` would follow each symlink and
    double-count every blob, inflating the estimate by ~2x and rejecting
    every large model that actually fits in memory. Skipping symlinks during
    traversal and summing only real files yields the true on-disk footprint.
    """
    total = 0
    for f in path.rglob("*"):
        if f.is_symlink():
            continue
        if f.is_file():
            total += f.stat().st_size
    return total / (1024**3)


def scan_models(hf_home: Path) -> list[tuple[str, Path]]:
    """Scan HF cache for mlx-community models, returning (model_id, path) pairs."""
    hub = hf_home / "hub"
    if not hub.is_dir():
        return []
    models = []
    for model_dir in sorted(hub.glob("models--mlx-community--*")):
        if not model_dir.is_dir():
            continue
        dir_name = model_dir.name
        model_id = dir_name.removeprefix("models--").replace("--", "/")
        models.append((model_id, model_dir))
    return models


def main() -> None:
    parser = argparse.ArgumentParser(description="Auto-discover MLX models")
    parser.add_argument("--quiet", action="store_true", help="Suppress output")
    parser.add_argument(
        "--dry-run", action="store_true", help="Show what would be registered"
    )
    args = parser.parse_args()

    hf_home = Path(os.environ.get("MLX_HF_HOME", "/Volumes/HuggingFace"))
    config_path = os.environ.get("MLX_LLAMA_SWAP_CONFIG")
    base_config_path = os.environ.get("MLX_LLAMA_SWAP_BASE_CONFIG")

    if not config_path:
        print("ERROR: MLX_LLAMA_SWAP_CONFIG not set", file=sys.stderr)
        sys.exit(1)
    if not base_config_path:
        print("ERROR: MLX_LLAMA_SWAP_BASE_CONFIG not set", file=sys.stderr)
        sys.exit(1)

    config_path = Path(config_path)
    base_config_path = Path(base_config_path)

    if not base_config_path.is_file():
        print(f"ERROR: Base config not found at {base_config_path}", file=sys.stderr)
        print("Run darwin-rebuild switch to generate it.", file=sys.stderr)
        sys.exit(1)

    if not config_path.is_file():
        print(
            f"ERROR: Runtime config not found at {config_path}",
            file=sys.stderr,
        )
        print(
            "Run darwin-rebuild switch to seed it (seed-config.py).",
            file=sys.stderr,
        )
        sys.exit(1)

    current_config = json.loads(config_path.read_text())

    # Extract default model and command template
    preload = (
        current_config.get("hooks", {}).get("on_startup", {}).get("preload", [])
    )
    if not preload:
        print(
            "ERROR: Could not determine default model from config", file=sys.stderr
        )
        sys.exit(1)
    default_model = preload[0]

    models_section = current_config.get("models", {})
    default_entry = models_section.get(default_model, {})
    cmd_template = default_entry.get("cmd", "")
    if not cmd_template:
        print(
            "ERROR: Could not extract command template from default model entry",
            file=sys.stderr,
        )
        sys.exit(1)

    model_env = default_entry.get("env", [])
    check_endpoint = default_entry.get("checkEndpoint", "/v1/models")
    idle_ttl = current_config.get("idleTtl", 1800)

    available_gb = get_memory_budget_gb()
    discovered = 0
    skipped = 0
    new_models: dict[str, dict] = {}
    new_members: list[str] = []

    for model_id, model_dir in scan_models(hf_home):
        # Skip non-generative models
        if EXCLUDE_PATTERN.search(model_id):
            if not args.quiet:
                print(f"SKIP: {model_id} (non-generative)", file=sys.stderr)
            skipped += 1
            continue

        # Skip if already in config
        if model_id in models_section:
            if not args.quiet:
                print(f"SKIP: {model_id} (already registered)", file=sys.stderr)
            continue

        # Memory preflight
        model_gb = dir_size_gb(model_dir)
        estimated_gb = round(model_gb * 1.3)

        if estimated_gb > available_gb:
            if not args.quiet:
                print(
                    f"SKIP: {model_id} ({estimated_gb} GB est. > {available_gb} GB available)",
                    file=sys.stderr,
                )
            skipped += 1
            continue

        model_cmd = cmd_template.replace(
            f"serve {default_model}", f"serve {model_id}"
        )

        entry = {
            "cmd": model_cmd,
            "ttl": idle_ttl,
            "env": model_env,
            "checkEndpoint": check_endpoint,
        }

        new_models[model_id] = entry
        new_members.append(model_id)

        if not args.quiet:
            print(f"ADD:  {model_id} ({model_gb} GB disk, {estimated_gb} GB est.)")
        discovered += 1

    if discovered == 0:
        if not args.quiet:
            print(f"No new models to register ({skipped} skipped).")
        sys.exit(0)

    if args.dry_run:
        print(f"DRY RUN: Would register {discovered} new models:")
        for model_id in new_models:
            print(f"  {model_id}")
        sys.exit(0)

    current_config.setdefault("models", {}).update(new_models)
    existing_members = (
        current_config.get("groups", {}).get("mlx-models", {}).get("members", [])
    )
    merged_members = sorted(set(existing_members + new_members))
    current_config.setdefault("groups", {}).setdefault("mlx-models", {})[
        "members"
    ] = merged_members

    # Write atomically
    config_dir = config_path.parent
    with tempfile.NamedTemporaryFile(
        mode="w", dir=config_dir, suffix=".tmp", delete=False
    ) as tmp:
        json.dump(current_config, tmp, indent=2)
        tmp.write("\n")
        tmp_path = Path(tmp.name)
    tmp_path.rename(config_path)

    if not args.quiet:
        print()
        print(f"Registered {discovered} new models ({skipped} skipped).")
        print("llama-swap will auto-reload the config.")


if __name__ == "__main__":
    main()
