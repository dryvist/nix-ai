#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <rendered-qwen-code-profile>" >&2
  exit 2
fi

exec bash "$(dirname "$0")/test-opencode-sandbox-escape.sh" "$1" qwen-code
