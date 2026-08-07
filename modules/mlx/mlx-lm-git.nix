# mlx-lm built from a pinned git revision — DeepSeek-V4 serving support.
#
# WHY A SECOND MLX-LM AT ALL
#
# No mlx-lm RELEASE carries a deepseek_v4 model implementation (checked
# 2026-08-06: latest release is the lib/versions.nix `mlxLm` pin, and upstream
# main has no deepseek_v4 module). Serving DeepSeek-V4 therefore needs source
# that only exists on a feature branch. This is a STAGED ROLLOUT state, not the
# architecture — lib/versions.nix `mlxLmGit` carries the removal criterion.
#
# The release wheel stays the default for everything else, because the harmony
# tool-call patch (./mlx-lm-patch.nix) is NOT ported here: gpt-oss served off
# this wheel would silently lose tool calling. The catalog assertion in
# ./options-catalog.nix is what enforces that, not this file.
#
# PATCHES ARE VENDORED, NEVER FETCHED
#
# ./mlx-lm-git-patches/ holds the diffs as committed files. Nothing is filed
# upstream and nothing is fetched from a pull request at build time — a PR can
# be force-pushed, rebased or closed, and a build that reaches out for one is a
# build whose inputs can change without the pin changing. Each patch's
# provenance is recorded next to the pin in lib/versions.nix. All three touch
# only mlx_lm/models/deepseek_v4.py and apply in any order (verified against
# the pinned rev), so the sequence numbers are naming, not a dependency.
#
# Returns the built wheel's absolute path — the same interface
# ./mlx-lm-patch.nix returns, so ./mlx-lm-server.nix consumes either one
# without caring which it got.
{ pkgs, mlxLmGit }:
let
  src = pkgs.applyPatches {
    name = "mlx-lm-src-deepseek-v4";
    src = pkgs.fetchFromGitHub {
      inherit (mlxLmGit)
        owner
        repo
        rev
        hash
        ;
    };
    patches = [
      ./mlx-lm-git-patches/0001-deepseek-v4-import-any.patch
      ./mlx-lm-git-patches/0002-deepseek-v4-per-layer-rope.patch
      ./mlx-lm-git-patches/0003-deepseek-v4-causal-comp-pool-mask.patch
      ./mlx-lm-git-patches/0004-deepseek-v4-drop-unused-mtp-heads.patch
    ];
  };

  # Built from setup.py (this tree ships no pyproject.toml), so the build needs
  # setuptools present rather than resolved: --no-isolation keeps the sandbox
  # offline. Runtime dependencies (mlx, transformers, ...) are deliberately NOT
  # supplied — the wheel only DECLARES them, and uv resolves them at serve time
  # exactly as it does for the release wheel.
  buildEnv = pkgs.python3.withPackages (ps: [
    ps.build
    ps.setuptools
    ps.wheel
  ]);

  wheelName = "mlx_lm-${mlxLmGit.version}-py3-none-any.whl";

  built =
    pkgs.runCommand "mlx-lm-wheel-git-${builtins.substring 0 7 mlxLmGit.rev}"
      {
        nativeBuildInputs = [ buildEnv ];
      }
      ''
        cp -r ${src} tree
        chmod -R u+w tree
        cd tree
        python -m build --wheel --no-isolation --outdir "$out"

        # The wheel filename is part of this file's return value, so a version
        # move on the pinned branch must fail the BUILD rather than resolve to
        # a path that does not exist at serve time.
        if [ ! -f "$out/${wheelName}" ]; then
          echo "expected $out/${wheelName}; the build produced:" >&2
          ls -1 "$out" >&2
          echo "update lib/versions.nix mlxLmGit.version to match." >&2
          exit 1
        fi
      '';
in
"${built}/${wheelName}"
