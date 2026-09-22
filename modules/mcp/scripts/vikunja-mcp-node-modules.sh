#!/usr/bin/env bash
# Build vikunja-mcp's production node_modules inside a fixed-output
# derivation. The npm tarball ships no package-lock.json, so this is a
# real `npm install` run against the npm registry — legitimate here only
# because it runs inside Nix's own network-sandboxed FOD build, pinned by
# outputHash, not as an interactive workstation command.
set -euo pipefail
export HOME="$TMPDIR"
npm install --omit=dev --no-audit --no-fund --ignore-scripts
mkdir -p "$out"
cp -r node_modules "$out/"
