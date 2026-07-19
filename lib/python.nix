# Single source of the CPython interpreter for the whole MLX stack.
#
# Core MLX is the PRIMARY DRIVER of this choice and of the mlx / mlx-lm /
# transformers pins in lib/versions.nix — they are ONE set. MLX's officially
# supported matrix (the MLX install docs on ml-explore.github.io) states Python
# 3.10 or newer with no upper bound, so the rule is: pick the newest CPython
# minor for which the pinned mlx version ships a wheel. mlx (currently 0.32.0)
# ships cp310 through cp314, so 3.14 is the newest in that envelope. Update the
# set together and deliberately from MLX's docs; never float one member.
#
# Renovate: the mlx / mlx-lm / transformers pins in lib/versions.nix are
# pypi-tracked and excluded from auto-bumps by nix-ai PR #1286. This python
# attribute is a plain nixpkgs attr with no renovate annotation, so renovate
# does not track it (nothing to exclude here).
#
# Consumed as `.pythonVersion` (=> "3.14") by every uvx / uv-run --python in the
# mlx module, so both cluster nodes resolve one CPython minor. Escalation path
# if the minor pin proves too loose (the two nodes resolving different 3.14.x
# patch builds): switch consumers from `.pythonVersion` to the interpreter path
# (lib.getExe' this "python3"), byte-identical across nodes on one nixpkgs rev.
#
# Change this one line when upgrading (e.g. python314 -> python315).
{ pkgs }: pkgs.python314
