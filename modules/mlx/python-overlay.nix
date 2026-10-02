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
# ATOMICITY
#
# mlx, mlx-lm and the Hugging Face libraries mlx-lm imports (transformers,
# tokenizers, safetensors, huggingface-hub, hf-xet) are all pinned in
# mlx-server/uv.lock, so the set the worker runs is the set Renovate moved, in
# one commit. They come from the published wheels (mlx-lm from its sdist, to
# carry the harmony patch), so overriding them compiles nothing; packages
# outside this list keep nixpkgs' versions.
#
# Before any NEW model family becomes a default, compare the chat template
# rendered with tools against the previous transformers — a future model may
# not render byte-identically:
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

  # Both wheels, with their hashes, come from mlx-server/uv.lock at the version
  # pinned there (lib/uv-lock.nix). A Renovate mlx bump regenerates the lock,
  # so the version and the hashes arrive in the same commit. A wheelPlatform
  # the lock does not list stops evaluation, naming the published tags.
  uvLock = import ../../lib/uv-lock.nix;
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

  # Platform tag regex for a wheel this host can install.
  hostPlatformTag =
    let
      arch = pkgs.stdenv.hostPlatform.parsed.cpu.name;
    in
    if pkgs.stdenv.hostPlatform.isDarwin then
      "macosx_[0-9_]+_${if arch == "aarch64" then "arm64" else arch}"
    else
      "manylinux[^-]*_${arch}";

  # The Hugging Face stack mlx-lm imports, at the versions in uv.lock: mlx-lm
  # 0.32.0 requires transformers>=5.7, which nixpkgs does not ship, and each
  # pulls the next floor up (tokenizers, safetensors, huggingface-hub, hf-xet,
  # click). Installed from the published wheels, so nothing here compiles.
  # Runtime dependencies are nixpkgs' list for the same package; the
  # runtime-deps check fails the build if a new release needs more.
  #
  # The value is pythonRelaxDeps. huggingface-hub declares click>=8.4.2 for its
  # `hf` CLI; nixpkgs ships an older click, and overriding click in this set
  # rebuilds torch from source through the test inputs of mlx-lm's checks.
  # Nothing in this env runs the `hf` CLI (that is the separate uvx `hf`
  # wrapper in modules/ai-tools.nix, which resolves its own click), so the
  # library keeps nixpkgs' click.
  lockWheels = {
    transformers = [ ];
    tokenizers = [ ];
    safetensors = [ ];
    huggingface-hub = [ "click" ];
    hf-xet = [ ];
  };
  fromLockWheel =
    super: name: relax:
    super.buildPythonPackage {
      pname = name;
      version = uvLock.version name;
      format = "wheel";
      src = pkgs.fetchurl (
        uvLock.hostWheel name {
          inherit cpTag;
          platform = hostPlatformTag;
        }
      );
      nativeBuildInputs = lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook;
      buildInputs = lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.stdenv.cc.cc.lib;
      dependencies = super.${name}.propagatedBuildInputs;
      pythonRelaxDeps = relax;
      pythonImportsCheck = [ (lib.replaceStrings [ "-" ] [ "_" ] name) ];
    };
in
py.override {
  self = py;
  packageOverrides =
    _self: super:
    lib.mapAttrs (fromLockWheel super) lockWheels
    // (lib.optionalAttrs useAppleWheel {
      mlx = super.buildPythonPackage {
        pname = "mlx";
        version = versions.mlx;
        format = "wheel";

        src = pkgs.fetchurl (uvLock.wheel "mlx" "${cpTag}-${cpTag}-${wheelPlatform}");

        nativeBuildInputs = [ pkgs.unzip ];
        propagatedBuildInputs = [ super.numpy ];

        # Overlay the Metal backend into the same site-packages, matching how the
        # two wheels compose in a venv. -o so the shared .py files resolve to
        # mlx-metal's copies, which is the order pip and uv produce.
        postInstall =
          let
            mlxMetalWheel = pkgs.fetchurl (uvLock.wheel "mlx-metal" "py3-none-${wheelPlatform}");
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
      # Built from the PyPI sdist pinned in mlx-server/uv.lock rather than
      # nixpkgs' own mlx-lm source, so the release the worker runs is the one
      # Renovate tracks. Stay on a RELEASE: catalog-lib.nix documents that the
      # git-wheel serverVariant DROPS --harmony-tool-parser, which gpt-oss needs.
      mlx-lm =
        let
          harmony = import ./mlx-lm-patch.nix { inherit pkgs; };
        in
        super.mlx-lm.overridePythonAttrs (old: {
          version = versions.mlxLm;
          inherit (harmony) src;
          # The sdist declares setuptools-scm as a build requirement (0.32.0+).
          build-system = (old.build-system or [ ]) ++ [ super.setuptools-scm ];
          postPatch = (old.postPatch or "") + harmony.postPatch;
        });
    };
}
