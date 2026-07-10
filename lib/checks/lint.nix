# Source-level quality checks — no home-manager evaluation needed
{ pkgs, src }:
{
  formatting = pkgs.runCommand "check-formatting" { } ''
    cp -r ${src} $TMPDIR/src
    chmod -R u+w $TMPDIR/src
    cd $TMPDIR/src
    ${pkgs.lib.getExe pkgs.nixfmt-tree} --fail-on-change --no-cache --tree-root $TMPDIR/src .
    touch $out
  '';

  statix = pkgs.runCommand "check-statix" { } ''
    cd ${src}
    ${pkgs.lib.getExe pkgs.statix} check .
    touch $out
  '';

  deadnix = pkgs.runCommand "check-deadnix" { } ''
    cd ${src}
    ${pkgs.lib.getExe pkgs.deadnix} -L --fail .
    touch $out
  '';

  # Lint shell scripts with shellcheck
  # Catches common bugs: unquoted variables, undefined vars, useless use of cat, etc.
  # Excludes .git directories and nix store paths
  # --severity=warning: Only fail on warning/error level (not info style suggestions)
  # SC1091: Exclude "not following" errors for external sources (can't resolve in Nix sandbox)
  # Excludes zsh scripts (shellcheck only supports sh/bash/dash/ksh)
  # Uses find with -print0 and xargs -0 for robustness with filenames containing spaces and special characters
  shellcheck = pkgs.runCommand "check-shellcheck" { } ''
    cd ${src}
    find . -name "*.sh" -not -path "./.git/*" -not -path "./result/*" -print0 | \
    xargs -0 bash -c '
      for script in "$@"; do
        # Skip zsh scripts (shellcheck does not support them)
        if head -1 "$script" | grep -q "zsh"; then
          echo "Skipping zsh script: $script"
        else
          echo "Checking $script..."
          ${pkgs.lib.getExe pkgs.shellcheck} --severity=warning --exclude=SC1091 "$script"
        fi
      done
    ' bash
    touch $out
  '';

  # Guard: physical MLX model ids belong only in the runtime registry
  # (services.aiStack.defaultLocalModelId, sourced from AI_MODEL_LOCAL_LLM).
  # Every consumer references a capability role, never a hardcoded id — so a
  # model swap touches only the registry. Allowed: the "mlx-community/<...>"
  # placeholder in option examples and the "test-model" id in the check harness.
  # lib/checks/* is excluded since it names the pattern itself, and
  # modules/mlx/catalog-data.nix is excluded because it IS the physical-id
  # SSOT (the validated model catalog every other reference resolves through).
  # modules/mlx/night-cluster.nix is the same kind of SSOT for the night
  # brain: a different engine (mlx-lm, not vllm-mlx) with exactly one model,
  # so the day catalog's role registry never references it.
  no-hardcoded-model-id = pkgs.runCommand "check-no-hardcoded-model-id" { } ''
    cd ${src}
    bad=$(grep -rnoE 'mlx-community/[A-Za-z0-9][^[:space:]"]*' \
      --include='*.nix' --include='*.sh' --include='*.md' \
      --exclude-dir=.git --exclude-dir=result --exclude-dir=.direnv . \
      | grep -vE 'lib/checks' \
      | grep -vE 'modules/mlx/catalog-data\.nix' \
      | grep -vE 'modules/mlx/night-cluster\.nix' \
      | grep -vE 'mlx-community/test-model' || true)
    if [ -n "$bad" ]; then
      echo "ERROR: hardcoded physical MLX model id(s) found — use an ai-stack capability role instead:" >&2
      echo "$bad" >&2
      exit 1
    fi
    echo "no hardcoded mlx-community/* model ids outside the registry/SSOT"
    touch $out
  '';
}
