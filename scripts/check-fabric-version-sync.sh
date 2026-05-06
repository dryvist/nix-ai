#!/usr/bin/env bash
# check-fabric-version-sync.sh
#
# CI guard: assert that the fabric version pin in flake.nix matches the
# version constant in lib/versions.nix.
#
# Why this exists:
#   - Renovate's `nix` manager bumps `flake.nix` flake input pins automatically
#   - The `fabric` entry in `lib/versions.nix` is managed by the custom.regex
#     manager — a separate Renovate PR
#   - If they drift, the build still works (fabric-src is the actual source)
#     but the version label becomes a lie
#
# The marketplace metadata version (used in fabric-curated-patterns marketplace)
# is derived at Nix eval time from lib/versions.nix — no separate sync needed.
#
# When to run:
#   - Pre-commit (manual)
#   - Pre-push CI check
#   - After every Renovate PR that touches flake.nix
#
# Exit codes:
#   0 = versions in sync
#   1 = drift detected (with descriptive error)
#   2 = parse error (file not found or pattern not matched)

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
flake_nix="${repo_root}/flake.nix"
versions_nix="${repo_root}/lib/versions.nix"

if [ ! -f "$flake_nix" ]; then
  echo "ERROR: flake.nix not found at $flake_nix" >&2
  exit 2
fi

if [ ! -f "$versions_nix" ]; then
  echo "ERROR: lib/versions.nix not found at $versions_nix" >&2
  exit 2
fi

# Extract fabric-src URL pin: github:danielmiessler/fabric/v1.4.444
# Looks for the line `url = "github:danielmiessler/fabric/v...";` inside the
# fabric-src input block.
flake_version=$(
  awk '/fabric-src = \{/,/\};/' "$flake_nix" \
    | grep -oE 'github:danielmiessler/fabric/v[0-9][^"]*' \
    | sed 's|github:danielmiessler/fabric/v||' \
    || true
)

if [ -z "$flake_version" ]; then
  echo "ERROR: could not parse fabric-src version from $flake_nix" >&2
  echo "Expected pattern: github:danielmiessler/fabric/v<VERSION>" >&2
  exit 2
fi

# Extract fabric version from lib/versions.nix via nix eval.
# The version is now an attrset entry, not a plain string in package.nix.
# The path is wrapped in Nix string quotes so that checkouts under directories
# with spaces (e.g. iCloud "Mobile Documents") still parse as a path literal.
package_version=$(
  nix eval --raw --impure --expr "(import \"${versions_nix}\").fabric" 2>/dev/null \
    || true
)

if [ -z "$package_version" ]; then
  echo "ERROR: could not evaluate lib/versions.nix.fabric" >&2
  echo "Expected: fabric = \"<VERSION>\"; in lib/versions.nix" >&2
  exit 2
fi

if [ "$flake_version" != "$package_version" ]; then
  echo "FAIL: fabric version drift detected" >&2
  echo "  flake.nix fabric-src:        v${flake_version}" >&2
  echo "  lib/versions.nix fabric:     ${package_version}" >&2
  echo "" >&2
  echo "The flake input pin and lib/versions.nix must stay in sync." >&2
  echo "Either Renovate bumped one but not the other, or you edited one" >&2
  echo "manually without updating the other." >&2
  echo "" >&2
  echo "Fix: update both to the same version, then run nix build .#fabric-ai" >&2
  echo "and update the vendorHash in modules/fabric/package.nix." >&2
  exit 1
fi

echo "OK: fabric version in sync (v${flake_version})"
exit 0
