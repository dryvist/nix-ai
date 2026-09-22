#!/usr/bin/env bash
# Unpack the published vikunja-mcp tarball and apply the local defect patch.
# Invoked from packages-npm.nix's patchedSrc derivation as:
#   vikunja-mcp-patch.sh <tarball> <patch-file> "$out"
set -euo pipefail
tarball="${1:?vikunja-mcp-patch: missing <tarball>}"
patch_file="${2:?vikunja-mcp-patch: missing <patch-file>}"
out="${3:?vikunja-mcp-patch: missing <out>}"
mkdir -p "$out"
tar xzf "$tarball" -C "$out" --strip-components=1
patch -p1 -d "$out" <"$patch_file"
