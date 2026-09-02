#!/usr/bin/env bash
# Test body for the no-ambient-secret-export check (lib/checks/lint.nix).
# Regression for the shell-init secret-export removal: nothing under this
# repo's shell-init sources (ai-aliases.zsh, endpoint.nix's rendered
# initContent) may unconditionally `export` an AppRole secret or the router
# bearer at login-shell startup — those must reach only the one child process
# that needs them (with-ai-readonly / the per-command wrapper functions in
# ai-stack/endpoint.nix), never the whole shell environment.
set -euo pipefail

out="${out:?out not set (expected from the Nix build environment)}"

# Two checks in one: a literal `export AI_READONLY_SECRET_ID=...`, and the
# exact dynamic-export idiom the pre-fix code used to smuggle a loop
# variable's value into the shell environment by name.
cd "$SRC"
bad=$( {
  grep -rnE '^\s*export\s+AI_READONLY_(ROLE|SECRET)_ID=' \
    --include='*.zsh' --include='*.nix' \
    --exclude-dir=.git --exclude-dir=result --exclude-dir=.direnv .
  # shellcheck disable=SC2016 # single-quoted on purpose: matching the shell
  # source's literal text, not expanding these vars in this script.
  grep -rn 'export "\$_ai_ro_var=\$_ai_ro_val"' \
    --include='*.zsh' \
    --exclude-dir=.git --exclude-dir=result --exclude-dir=.direnv .
} || true)
if [ -n "$bad" ]; then
  echo "ERROR: unconditional shell-init export of an OpenBao AppRole credential found — scope it to the one command that needs it instead (see with-ai-readonly in modules/ai-aliases.zsh):" >&2
  echo "$bad" >&2
  exit 1
fi
echo "no ambient shell-init export of an OpenBao AppRole credential"
touch "$out"
