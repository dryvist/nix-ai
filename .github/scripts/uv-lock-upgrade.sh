#!/usr/bin/env bash
# Refresh uv lockfiles to the latest versions each pyproject.toml allows.
#
# WHY: Renovate cannot clear the transitive PyPI vulnerabilities the OSV gate
# (.github/workflows/ci-gate.yml -> osv-scan) flags — they are transitive deps
# not declared in pyproject.toml, GitHub Dependabot raises no alert for them,
# and Renovate's OSV path reports "no CVEs found". Plain `uv lock` preserves
# stale transitive pins, so only an explicit `uv lock --upgrade` moves them.
# uv-lock-upgrade.yml runs this twice weekly and auto-merges the result.
#
# SAFETY: pyproject constraints are the rail. mlx-server pins
# mlx>=0.31.1,<0.31.2 and mlx-lm>=0.31.1,<0.31.3, so --upgrade cannot reach the
# broken mlx 0.31.2/0.31.3 window (nix-ai#751); orchestrator's [tool.uv]
# constraint-dependencies hold the litellm/langsmith security floors.
set -euo pipefail

projects=("$@")
if [ "${#projects[@]}" -eq 0 ]; then
  projects=(mlx-server orchestrator)
fi

# ::group:: / ::endgroup:: are GitHub Actions workflow commands. Emit them only
# under Actions so local runs (a developer manually refreshing lockfiles) get
# clean output instead of literal "::group::" noise.
group() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::group::$*"; else echo "$*"; fi; }
endgroup() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::endgroup::"; fi; }

for project in "${projects[@]}"; do
  group "uv lock --upgrade ${project}"
  uv lock --upgrade --directory "${project}"
  endgroup
done
