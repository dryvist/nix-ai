#!/usr/bin/env bash
# Runtime half of the mlx-default-model check: drive the real default-model.py
# against a fixture llama-swap config and assert every branch, especially the
# loud ones. Env from lib/checks/mlx-default-model.nix:
#   SCRIPT   default-model.py
#   FIXTURE  starting llama-swap config
#   DECLARED / OVERRIDE  the two catalog keys' physical ids
set -euo pipefail

export MLX_LLAMA_SWAP_CONFIG="$PWD/llama-swap.json"
export MLX_DEFAULT_MODEL_OVERRIDE="$PWD/default-model.override"
CONFIG=$MLX_LLAMA_SWAP_CONFIG

run() { python3 "$SCRIPT" "$@"; }
aliases() { jq -c --arg m "$1" '.models[$m].aliases' "$CONFIG"; }

cp "$FIXTURE" "$CONFIG"
chmod u+w "$CONFIG"

# No override: the declared default keeps the alias, and nothing shouts.
run apply > no-override.log
[ ! -s no-override.log ] || {
  echo "apply printed a banner with no override in effect:" >&2
  cat no-override.log >&2
  exit 1
}
[ "$(aliases "$DECLARED")" = '["default","coding"]' ] || {
  echo "declared default lost its alias: $(aliases "$DECLARED")" >&2
  exit 1
}

# set: alias moves, and the banner names BOTH declared and override.
run set qwen36-35b > set.log
[ "$(aliases "$OVERRIDE")" = '["goal-judge","default"]' ] || {
  echo "override target did not receive the default alias" >&2
  exit 1
}
[ "$(aliases "$DECLARED")" = '["coding"]' ] || {
  echo "declared default kept the alias, so two models answer to it" >&2
  exit 1
}
grep -q "MLX DEFAULT MODEL OVERRIDE ACTIVE" set.log || {
  echo "override took effect silently — the whole point is that it cannot" >&2
  exit 1
}
grep -q "qwen38-27b" set.log && grep -q "qwen36-35b" set.log || {
  echo "banner must state the declared value AND the overridden value" >&2
  exit 1
}

# apply is idempotent and re-announces on every activation.
run apply | grep -q "MLX DEFAULT MODEL OVERRIDE ACTIVE"
[ "$(aliases "$OVERRIDE")" = '["goal-judge","default"]' ]

# Unusable key: loud on stderr, declared default served, exit 0 so a stale
# override file cannot abort a rebuild.
echo "not-a-catalog-key" > "$MLX_DEFAULT_MODEL_OVERRIDE"
run apply 2> invalid.log
grep -q "not a catalog key" invalid.log || {
  echo "an unusable override must say why:" >&2
  cat invalid.log >&2
  exit 1
}
[ "$(aliases "$DECLARED")" = '["coding","default"]' ] || {
  echo "invalid override must fall back to the declared default" >&2
  exit 1
}
run show | grep -q "UNUSABLE"

# set rejects an unknown key outright rather than writing the file.
cp "$MLX_DEFAULT_MODEL_OVERRIDE" before-set
! run set nope 2> rejected.log
grep -q "cannot set default" rejected.log
cmp -s before-set "$MLX_DEFAULT_MODEL_OVERRIDE"

# clear: file gone, declared default keeps the alias, show says so.
run clear > /dev/null
[ ! -e "$MLX_DEFAULT_MODEL_OVERRIDE" ]
[ "$(aliases "$DECLARED")" = '["coding","default"]' ]
run show | grep -q "serving the declared default"

# No declared key at all (a host that has not adopted the option). The alias
# comes from a catalog entry's own roles list, so apply must leave it alone.
jq '{declared: null, keys: .keys}' "$MLX_DEFAULT_MODEL_KEYMAP" > nodecl.json
MLX_DEFAULT_MODEL_KEYMAP=$PWD/nodecl.json run apply 2> nodecl.log
[ ! -s nodecl.log ] || {
  echo "an entry-declared default must not be flagged:" >&2
  cat nodecl.log >&2
  exit 1
}
[ "$(aliases "$DECLARED")" = '["coding","default"]' ]

# ...but nothing holding the alias at all is a real fault and must be loud,
# never the same bare return as "nothing to do".
jq 'del(.models[].aliases)' "$CONFIG" > noalias.json
mv noalias.json "$CONFIG"
MLX_DEFAULT_MODEL_KEYMAP=$PWD/nodecl.json run apply 2> orphan.log
grep -q 'no model holds the "default" alias' orphan.log || {
  echo "a config with no default alias must fail loudly, not silently" >&2
  cat orphan.log >&2
  exit 1
}
