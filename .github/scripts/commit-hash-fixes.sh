#!/usr/bin/env bash
set -euo pipefail
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add modules/cecli/package.nix modules/mlx/llama-swap.nix
git diff --cached --quiet && exit 0
git commit -m "fix(deps): update package hashes after a version bump"
git push
