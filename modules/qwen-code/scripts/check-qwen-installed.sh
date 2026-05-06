#!/usr/bin/env bash
#
# Soft check: warn (don't fail) when programs.qwen-code is enabled with
# installVia="brew" but the qwen binary is not on PATH yet. The brew
# install actually lives in nix-darwin's homebrew.brews block — sourced
# from nix-ai's lib.brewFormulae flake output. Until the user runs the
# companion nix-darwin rebuild, the binary won't be present.

set -eu

if ! command -v qwen >/dev/null 2>&1; then
  echo "WARNING: programs.qwen-code is enabled but \`qwen\` is not on PATH." >&2
  echo "  Add \"qwen-code\" to homebrew.brews in nix-darwin and rebuild." >&2
fi
