# The MLX Python stack as Nix derivations, with a working Metal backend.
#
# WHY THIS EXISTS
#
# The serving stack used to be delivered by `uv run --with`, which mints a
# COMPLETE ~1.4 GB venv per distinct resolution under ~/.cache/uv/archive-v0
# with hardlink count 1 (no sharing between them) and never evicts one. There
# are no GC roots and no TTL, so the cache grew to 328 GB on the laptop — five
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
# ATOMICITY, AND WHY transformers IS DELIBERATELY *NOT* PINNED HERE
#
# mlx and mlx-lm are pinned together from lib/versions.nix, so a partial bump of
# that pair is unrepresentable rather than merely prohibited by a Renovate
# exclusion a config edit could get wrong.
#
# transformers rides whatever nixpkgs ships. This IS a deliberate divergence
# from lib/versions.nix, which governs the uvx path — record it in review rather
# than "fixing" it by adding a pin.
#
# Pinning it was tried and reverted 2026-08-14. transformers enforces its own
# dependency floors at IMPORT time (transformers/dependency_versions_check.py),
# not just in metadata, so `dontCheckRuntimeDeps` does not help: the pinned
# version demanded a newer safetensors than nixpkgs carries and failed its
# import check during activation. Satisfying it means also overriding
# safetensors, and then whatever that pulls — and because transformers is a
# shared dependency, the rebuild reached accelerate, peft, and lm-eval as well.
# A large, cascading override of a shared package is a worse trade than the
# divergence.
#
# The divergence is measured, not assumed. On 2026-08-14 the nixpkgs version and
# the pinned version rendered a BYTE-IDENTICAL chat template with tools against
# the real model snapshot, so tool-parser selection and the bytes reaching the
# model are unchanged. Re-run that comparison before making any NEW model family
# a default — a future model may not be as forgiving:
#
#   apply_chat_template(msgs, tools=..., add_generation_prompt=True)
#   -> compare len + sha256 across both versions (jinja2 must be installed;
#      transformers alone does not pull it and apply_chat_template ImportErrors)
{
  pkgs,
  versions,
  # Wheel platform tag. Apple publishes one wheel per macOS deployment target;
  # uv resolves the highest the running OS supports, which is macosx_26_0 on
  # both Macs today (the laptop verified at macOS 26.5.2). Pinning that keeps
  # behavior identical to the uv path. A node on an older macOS must override
  # this to its own target — the derivation would still BUILD (it only fetches
  # and unzips) but the dylib would fail to load at import.
  wheelPlatform ? "macosx_26_0_arm64",
}:
let
  inherit (pkgs) lib;
  py = import ../../lib/python.nix { inherit pkgs; };
  # "3.14" -> "cp314", the wheel's interpreter/ABI tag.
  cpTag = "cp" + (pkgs.lib.replaceStrings [ "." ] [ "" ] py.pythonVersion);

  # Keyed by mlx VERSION ONLY, and valid for the default wheelPlatform above.
  # A caller that overrides wheelPlatform fetches a different wheel while this
  # map still hands back the default platform's hash, so the fetch fails on a
  # hash mismatch. That is loud, not silent — nix verifies the hash — but it is
  # a mismatch error rather than a message about the override, so: overriding
  # wheelPlatform means supplying hashes for that platform too. No platform
  # dimension is modelled here because every host this serves resolves the same
  # target; add one when that stops being true rather than in advance.
  #
  # Both wheels move together with the mlx pin in lib/versions.nix; bumping the
  # pin without updating these fails the build loudly rather than silently
  # resolving something else.
  #
  # THE PIN AND THIS TABLE ARE UPDATED BY DIFFERENT HANDS. Renovate moves
  # versions.mlx on its own and knows nothing about this map, so an automated
  # bump lands a version with no entry here and every aarch64-darwin build
  # stops at the throw below. That is the designed behaviour, not a surprise --
  # but it means a renovate mlx PR is not complete until someone adds the row.
  #
  # To add one, take the version from lib/versions.nix and prefetch both wheels
  # for this file's cpTag and wheelPlatform:
  #
  #   nix-prefetch-url --type sha256 <pypi url for mlx-<v>-cp314-cp314-<plat>.whl>
  #   nix-prefetch-url --type sha256 <pypi url for mlx_metal-<v>-py3-none-<plat>.whl>
  #   nix hash convert --hash-algo sha256 --to sri <each result>
  #
  # Superseded versions are kept rather than replaced: the map is keyed by the
  # pin, so there is no ambiguity about which row is live, and keeping them
  # means rolling the pin back does not also require re-deriving hashes.
  wheelHashes = {
    "0.32.0" = {
      mlx = "sha256-I+g8jnSiMVZpbp+ZBdFqF7fSe1pZbBvA9yCpjfHFqt8=";
      mlxMetal = "sha256-OvdqSY2EgE9mEZgASZ+dFD19/7CHig3Q18KEblhWX9c=";
    };
    "0.32.2" = {
      mlx = "sha256-NQNhfjqmqOQR31MjbVvKA5/MqXVW8a3hxOXMimTeUtI=";
      mlxMetal = "sha256-5qvqyaxSZYMMnBVBtvlum+N6hcJEZ2OkatRmxjo4N6s=";
    };
  };

  # The message names the platform actually in effect, so an override that
  # needs its own hashes says which target to prefetch for.
  hashes =
    wheelHashes.${versions.mlx}
      or (throw "python-overlay.nix: no wheel hashes for mlx ${versions.mlx}. Add them to wheelHashes (nix-prefetch-url the ${cpTag}/${wheelPlatform} wheels from PyPI).");
  # Apple publishes mlx wheels for aarch64-darwin only, so the override below
  # cannot build anywhere else. CI evaluates and BUILDS the home-manager config
  # on x86_64-linux, which reached this package through the serving wrapper and
  # failed with "No module named 'mlx.core'" — the wheel has no Linux artifact.
  #
  # Off Apple silicon, fall back to nixpkgs' mlx. That build is CPU-only (see
  # the header) and is NEVER what serves: this module's consumers are Macs. It
  # exists so the config still evaluates on the CI system. The mlx-lm harmony
  # patch below stays unconditional, so CI still builds and tests it.
  useAppleWheel = pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64;
in
py.override {
  self = py;
  packageOverrides =
    _self: super:
    (lib.optionalAttrs useAppleWheel {
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
    })
    // {
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
