# The MLX Python stack as Nix derivations, with a working Metal backend.
#
# WHY THIS EXISTS
#
# The serving stack used to be delivered by `uv run --with`, which mints a
# COMPLETE ~1.4 GB venv per distinct resolution under ~/.cache/uv/archive-v0
# with hardlink count 1 (no sharing between them) and never evicts one. There
# are no GC roots and no TTL, so the cache grew to 328 GB on jevans-mbp — five
# times the entire 62 GB Nix store for the whole system. Worse, every live uvx
# process holds a shared lock on ~/.cache/uv/.lock, so `uv cache prune` could
# never take the exclusive lock and exited 0 having freed nothing. Delivering
# the same packages from the store instead gets dedup, GC roots, and the
# weekly nix-collect-garbage this host already runs.
#
# WHY NOT nixpkgs' python3xxPackages.mlx
#
# nixpkgs builds mlx from source with -DMLX_BUILD_METAL:BOOL=FALSE, because
# compiling Metal shaders needs Xcode's proprietary toolchain and that cannot
# run in the Nix sandbox. The resulting package imports fine and runs on CPU,
# so it LOOKS healthy — `mx.metal.is_available()` returns False and opening a
# GPU stream raises "Cannot get gpu stream without gpu backend". Verified on
# aarch64-darwin 2026-08-14. Anything measuring performance against that build
# is silently benchmarking the CPU.
#
# So mlx comes from Apple's official PyPI wheel, which ships Metal
# precompiled. Upstream splits the backend into a SEPARATE `mlx-metal` wheel
# carrying libmlx.dylib / mlx.metallib / libjaccl.dylib. Both wheels install
# into the same `mlx/` package directory and overlap on several .py files, so
# they cannot be two derivations composed by buildEnv — buildEnv refuses
# conflicting subpaths, whereas a venv "works" only because the second install
# silently overwrites the first. Installing both into ONE derivation
# reproduces that layout honestly.
#
# ATOMICITY
#
# mlx / mlx-lm / transformers are ONE set — see lib/python.nix — and all three
# are pinned here from lib/versions.nix. Expressing them in a single overlay
# makes a partial bump unrepresentable, rather than merely prohibited by a
# Renovate exclusion that a config edit could get wrong.
#
# transformers is pinned rather than left at whatever nixpkgs ships. nixpkgs
# currently carries a version roughly ten minors behind the pin. Measured
# 2026-08-14 against the real model snapshot, both render a BYTE-IDENTICAL chat
# template with tools, so parser selection and the bytes reaching the model are
# unchanged — no breakage was found either way. It is pinned because
# lib/versions.nix declares itself the single source of truth for shared deps,
# and letting one path silently follow a different number contradicts that; the
# drift stays invisible until some future model exposes it.
{
  pkgs,
  versions,
  # Wheel platform tag. Apple publishes one wheel per macOS deployment target;
  # uv resolves the highest the running OS supports, which is macosx_26_0 on
  # both Macs today (jevans-mbp verified at macOS 26.5.2). Pinning that keeps
  # behavior identical to the uv path. A node on an older macOS must override
  # this to its own target — the derivation would still BUILD (it only fetches
  # and unzips) but the dylib would fail to load at import.
  wheelPlatform ? "macosx_26_0_arm64",
}:
let
  py = (import ../../lib/python.nix { inherit pkgs; });
  # "3.14" -> "cp314", the wheel's interpreter/ABI tag.
  cpTag = "cp" + (pkgs.lib.replaceStrings [ "." ] [ "" ] py.pythonVersion);

  # Hashes are per (version, platform). Both wheels move together with the mlx
  # pin in lib/versions.nix; bumping the pin without updating these fails the
  # build loudly rather than silently resolving something else.
  wheelHashes = {
    "0.32.0" = {
      mlx = "sha256-I+g8jnSiMVZpbp+ZBdFqF7fSe1pZbBvA9yCpjfHFqt8=";
      mlxMetal = "sha256-OvdqSY2EgE9mEZgASZ+dFD19/7CHig3Q18KEblhWX9c=";
    };
  };

  # The transformers SDIST hash. One per version, platform-independent — unlike
  # the mlx wheels above, which are per macOS deployment target.
  transformersHashes = {
    "5.15.0" = "sha256-u/mPV7Ld18TsvM+iwAaQF6pv0BzCBL1Qy8Durc8qE7g=";
  };
  transformersHash =
    transformersHashes.${versions.transformers}
      or (throw "python-overlay.nix: no wheel hash for transformers ${versions.transformers}. Add it to transformersHashes (the .tar.gz sdist on PyPI).");
  hashes =
    wheelHashes.${versions.mlx}
      or (throw "python-overlay.nix: no wheel hashes for mlx ${versions.mlx}. Add them to wheelHashes (nix-prefetch-url the cp${cpTag}/${wheelPlatform} wheels from PyPI).");
in
py.override {
  self = py;
  packageOverrides = _self: super: {
    mlx = super.buildPythonPackage {
      pname = "mlx";
      version = versions.mlx;
      format = "wheel";

      src = super.fetchPypi {
        pname = "mlx";
        version = versions.mlx;
        format = "wheel";
        dist = cpTag;
        python = cpTag;
        abi = cpTag;
        platform = wheelPlatform;
        hash = hashes.mlx;
      };

      nativeBuildInputs = [ pkgs.unzip ];
      propagatedBuildInputs = [ super.numpy ];

      # Overlay the Metal backend into the same site-packages, matching how the
      # two wheels compose in a venv. -o so the shared .py files resolve to
      # mlx-metal's copies, which is the order pip and uv produce.
      postInstall =
        let
          mlxMetalWheel = super.fetchPypi {
            pname = "mlx_metal";
            version = versions.mlx;
            format = "wheel";
            dist = "py3";
            python = "py3";
            abi = "none";
            platform = wheelPlatform;
            hash = hashes.mlxMetal;
          };
        in
        ''
          unzip -qo ${mlxMetalWheel} -d $out/${py.sitePackages}
        '';

      # mlx-metal is vendored above rather than installed as its own dist, so
      # the runtime-deps check cannot see it and would fail on "not installed".
      dontCheckRuntimeDeps = true;
      pythonImportsCheck = [ "mlx" ];
    };

    # Pinned to lib/versions.nix rather than riding whatever nixpkgs ships, so
    # one number governs both this path and the uvx path. Rationale and the
    # byte-identical-template measurement are in the header.
    transformers = super.transformers.overridePythonAttrs (old: {
      version = versions.transformers;
      # The sdist, not the wheel: nixpkgs builds transformers as a `pyproject`
      # derivation, and mk-python-derivation asserts pyproject and an explicit
      # `format` are mutually exclusive. Overriding only version+src keeps the
      # existing build style and makes this a two-line change.
      src = super.fetchPypi {
        pname = "transformers";
        version = versions.transformers;
        hash = transformersHash;
      };
      # nixpkgs pins patches to the version it ships; they will not apply to a
      # newer sdist.
      patches = [ ];
      # Upstream moves its dependency floors between minors, and this jumps
      # several. The set is validated by the harmony tests and a live generate
      # rather than by nixpkgs' metadata check.
      dontCheckRuntimeDeps = true;
      doCheck = false;
      pythonImportsCheck = old.pythonImportsCheck or [ "transformers" ];
    });

    # mlx-lm carrying the harmony (gpt-oss) tool-call parser. The defect and
    # the patch's degradation contract are documented in mlx-lm-patch.nix; only
    # the delivery mechanism changes here. Previously the PyPI wheel was
    # unzipped, patched, and rezipped because that "needs no build step"; a
    # nixpkgs source derivation makes it an ordinary postPatch, which is both
    # smaller and keeps nixpkgs' own check phase.
    #
    # The pin stays on the 0.31.3 RELEASE. mlx-lm 0.31.3 is upstream's newest
    # (not a stale pin), and catalog-lib.nix documents that the only route past
    # it is a git-wheel serverVariant that DROPS --harmony-tool-parser, which
    # gpt-oss needs. Release-plus-patch is therefore the only viable route —
    # do not drift toward the git wheel.
    mlx-lm = super.mlx-lm.overridePythonAttrs (old: {
      postPatch = (old.postPatch or "") + (import ./mlx-lm-patch.nix { inherit pkgs; }).postPatch;
    });
  };
}
