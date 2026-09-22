#!/usr/bin/env bash
# Assemble the vikunja-mcp store output: patched dist/ + linked node_modules
# + a node wrapper. Invoked from packages-npm.nix as:
#   vikunja-mcp-install.sh <node-modules-store-path> "$out"
set -euo pipefail
node_modules_out="${1:?vikunja-mcp-install: missing <node-modules-store-path>}"
out="${2:?vikunja-mcp-install: missing <out>}"
mkdir -p "$out/lib/vikunja-mcp"
cp -r dist "$out/lib/vikunja-mcp/dist"
ln -s "$node_modules_out/node_modules" "$out/lib/vikunja-mcp/node_modules"
makeWrapper "$NODE_BIN" "$out/bin/vikunja-mcp" \
  --add-flags "$out/lib/vikunja-mcp/dist/index.js"
