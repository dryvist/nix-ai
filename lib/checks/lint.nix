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
  shellcheck =
    pkgs.runCommand "check-shellcheck"
      {
        # shellcheck's GHC runtime encodes stdout with the process locale's charset;
        # under the default C/POSIX locale a non-ASCII byte in a reported source line
        # (e.g. an em-dash in a comment) aborts it with
        # "commitBuffer: invalid argument (cannot encode character)" instead of
        # printing the finding. Pin a UTF-8 locale so any script's UTF-8 content is
        # emitted, not fatal — the check tests scripts, it must not crash on them.
        LANG = "C.UTF-8";
        LC_ALL = "C.UTF-8";
      }
      ''
        cd ${src}
        find . -name "*.sh" -not -path "./.git/*" -not -path "./result/*" -print0 | \
        xargs -0 bash -c '
          failed=0
          for script in "$@"; do
            # Skip zsh scripts (shellcheck does not support them)
            if head -1 "$script" | grep -q "zsh"; then
              echo "Skipping zsh script: $script"
            else
              echo "Checking $script..."
              if ! ${pkgs.lib.getExe pkgs.shellcheck} --severity=warning --exclude=SC1091 "$script"; then
                failed=1
              fi
            fi
          done
          exit "$failed"
        ' bash
        touch $out
      '';

  # Guard: every script under modules/scripts/ must carry the executable bit.
  #
  # Those scripts are invoked by home-manager wrappers that exec an interpolated
  # store path directly, rather than handing it to a shell. A store path inherits the source tree's mode, so a file committed 100644
  # lands non-executable and the wrapper dies with exit 126 ("Permission
  # denied") BEFORE the script's first line runs — no log output, no alert, and
  # a launchd agent that looks scheduled while doing nothing. That shipped once
  # (the litellm fallback watcher, 2026-09-01) and survived a rehearsal, because
  # the rehearsal invoked the script as `bash <path>`, which never consults the
  # mode. Its sibling probe worked only because its mode happened to be right.
  #
  # Deliberately scoped to modules/scripts/: that directory holds only
  # wrapper-executed scripts. Elsewhere an interpolated store path may sit in
  # argument position — lib/checks/mcp.nix hands one to a `bash` test harness —
  # where no executable bit is needed and a broader scan would false-positive.
  # Scripts consumed with builtins.readFile (modules/mlx/scripts, and others)
  # are inlined as text and likewise need no mode.
  script-exec-bits = pkgs.runCommand "check-script-exec-bits" { } ''
    found=0
    failed=0
    for script in ${src}/modules/scripts/*.sh; do
      found=$((found + 1))
      if [ ! -x "$script" ]; then
        echo "ERROR: modules/scripts/$(basename "$script") is not executable — a wrapper that execs it fails with exit 126 before running" >&2
        failed=1
      fi
    done
    if [ "$found" -eq 0 ]; then
      echo "ERROR: no scripts found under modules/scripts/ — this check would pass vacuously" >&2
      exit 1
    fi
    if [ "$failed" -ne 0 ]; then
      echo "Fix with: git update-index --chmod=+x <file> && chmod +x <file>" >&2
      exit 1
    fi
    echo "all $found script(s) under modules/scripts/ are executable"
    touch $out
  '';

  # Guard: physical MLX model ids belong only in the runtime registry
  # (services.aiStack.defaultLocalModelId, sourced from AI_MODEL_LOCAL_LLM).
  # Every consumer references a capability role, never a hardcoded id — so a
  # model swap touches only the registry. Allowed: the "mlx-community/<...>"
  # placeholder in option examples and the "test-model" id in the check harness.
  # lib/checks/* is excluded since it names the pattern itself, and the catalog
  # data files are excluded because they ARE the physical-id SSOT (the validated
  # model catalog every other reference resolves through).
  #
  # The catalog exclusion is a PATTERN, catalog-data.nix plus any
  # catalog-data-<entry>.nix, rather than a list of filenames. Those siblings
  # exist only because catalog-data.nix keeps crossing the per-file size gate
  # and entries get carved out of it — so an enumerated list makes every future
  # split fail this check for a reason that has nothing to do with the rule it
  # enforces. That happened once already (the qwen38-27b split), and the fix is
  # the pattern, not another line. The exclusion stays narrow: it admits catalog
  # data files by name, nothing else in modules/mlx.
  # modules/mlx/cluster-mode.nix (and its extracted option file
  # modules/mlx/options-cluster.nix, which holds the clusterMode.model default)
  # are the same kind of SSOT for the clustered-mode model: a different engine
  # (mlx-lm, not vllm-mlx) with exactly one model, so the normal-mode catalog's
  # role registry never references it.
  no-hardcoded-model-id = pkgs.runCommand "check-no-hardcoded-model-id" { } ''
    cd ${src}
    bad=$(grep -rnoE 'mlx-community/[A-Za-z0-9][^[:space:]"]*' \
      --include='*.nix' --include='*.sh' --include='*.md' \
      --exclude-dir=.git --exclude-dir=result --exclude-dir=.direnv . \
      | grep -vE 'lib/checks' \
      | grep -vE 'modules/mlx/catalog-data(-[a-z0-9-]+)?\.nix' \
      | grep -vE 'modules/mlx/cluster-mode\.nix' \
      | grep -vE 'modules/mlx/options-cluster\.nix' \
      | grep -vE 'mlx-community/test-model' || true)
    if [ -n "$bad" ]; then
      echo "ERROR: hardcoded physical MLX model id(s) found — use an ai-stack capability role instead:" >&2
      echo "$bad" >&2
      exit 1
    fi
    echo "no hardcoded mlx-community/* model ids outside the registry/SSOT"
    touch $out
  '';

  # Regression for the OpenBao AppRole shell-init secret-export removal —
  # see scripts/no-ambient-secret-export.sh for the rationale.
  no-ambient-secret-export = pkgs.runCommand "check-no-ambient-secret-export" { SRC = src; } ''
    ${pkgs.bash}/bin/bash ${./scripts/no-ambient-secret-export.sh}
  '';
}
