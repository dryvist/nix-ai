#!/usr/bin/env python3
"""Seed llama-swap runtime config from the Nix-generated base config.

Called by home.activation on darwin-rebuild switch. Preserves
runtime-discovered models by only overwriting when the base config
has actually changed (tracked via .base-config-hash marker file).

Arguments:
  $1 - path to Nix-generated base config (immutable Nix store)
  $2 - path to mutable runtime config (read by llama-swap)
"""

import hashlib
import os
import sys
import tempfile
from pathlib import Path


def _atomic_write(target: Path, content: bytes) -> None:
    """Write ``content`` to ``target`` atomically with user-writable mode.

    shutil.copy2 would preserve the read-only mode of the Nix-store source,
    making the runtime config un-overwritable on the next activation. Using
    tmp + os.replace gives us atomicity, an explicit 0o644 mode, and clear
    swap semantics even when the target already exists.
    """
    fd, tmp = tempfile.mkstemp(
        dir=target.parent, prefix=target.name + ".", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(content)
        os.chmod(tmp, 0o644)
        os.replace(tmp, target)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise



def main() -> None:
    if len(sys.argv) != 3:
        print(
            "Usage: seed-config.py <base-config> <runtime-config>", file=sys.stderr
        )
        sys.exit(1)

    base = Path(sys.argv[1])
    runtime = Path(sys.argv[2])
    runtime.parent.mkdir(parents=True, exist_ok=True)

    base_content = base.read_bytes()
    base_hash = hashlib.sha256(base_content).hexdigest()
    marker = runtime.parent / ".base-config-hash"

    # Atomically create runtime config if it doesn't exist (avoids TOCTOU race
    # with concurrent darwin-rebuild or LaunchAgent startup).
    try:
        fd = os.open(str(runtime), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        with os.fdopen(fd, "wb") as f:
            f.write(base_content)
        marker.write_text(base_hash + "\n")
        print("Seeded llama-swap runtime config from Nix store")
        return
    except FileExistsError:
        pass

    prev_hash = marker.read_text().strip() if marker.exists() else ""

    if base_hash != prev_hash:
        _atomic_write(runtime, base_content)
        marker.write_text(base_hash + "\n")
        print("Updated llama-swap runtime config (base config changed)")
    else:
        print("llama-swap runtime config unchanged (base hash matches)")


if __name__ == "__main__":
    main()
