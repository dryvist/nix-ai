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
# one commit. They come from the published wheels (mlx-lm from its sdist), so
# overriding them compiles nothing; packages
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
  # Apple silicon takes the Metal backend wheel. Linux, which never serves but
  # where CI builds and tests this env, takes Apple's CPU backend wheel at the
  # same version: nixpkgs' from-source mlx trails the pin, and mlx-lm's own
  # tests crash against an mlx older than the one it requires.
  useAppleWheel = pkgs.stdenv.hostPlatform.isDarwin && pkgs.stdenv.hostPlatform.isAarch64;
  inherit (pkgs.stdenv.hostPlatform) isLinux;

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
      # hf-xet writes a log under $HOME when imported.
      nativeBuildInputs = [
        pkgs.writableTmpDirAsHomeHook
      ]
      ++ lib.optional isLinux pkgs.autoPatchelfHook;
      buildInputs = lib.optional isLinux pkgs.stdenv.cc.cc.lib;
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
    // (lib.optionalAttrs (useAppleWheel || isLinux) {
      mlx = super.buildPythonPackage {
        pname = "mlx";
        version = versions.mlx;
        format = "wheel";

        src = pkgs.fetchurl (
          if useAppleWheel then
            uvLock.wheel "mlx" "${cpTag}-${cpTag}-${wheelPlatform}"
          else
            uvLock.hostWheel "mlx" {
              inherit cpTag;
              platform = hostPlatformTag;
            }
        );

        nativeBuildInputs = [ pkgs.unzip ] ++ lib.optional isLinux pkgs.autoPatchelfHook;
        buildInputs = lib.optional isLinux pkgs.stdenv.cc.cc.lib;
        propagatedBuildInputs = [ super.numpy ];

        # Overlay the backend (mlx-metal, or mlx-cpu on Linux) into the same
        # site-packages, matching how the two wheels compose in a venv. -o so
        # the shared .py files resolve to the backend's copies, which is the
        # order pip and uv produce.
        postInstall =
          let
            backendWheel = pkgs.fetchurl (
              if useAppleWheel then
                uvLock.wheel "mlx-metal" "py3-none-${wheelPlatform}"
              else
                uvLock.hostWheel "mlx-cpu" {
                  inherit cpTag;
                  platform = hostPlatformTag;
                }
            );
          in
          ''
            unzip -qo ${backendWheel} -d $out/${py.sitePackages}
          '';

        # The backend is vendored above rather than installed as its own dist,
        # so the runtime-deps check cannot see it and would fail on "not
        # installed".
        dontCheckRuntimeDeps = true;
        pythonImportsCheck = [ "mlx.core" ];
      };
    })
    // {
      # mlx-lm built from the PyPI sdist pinned in mlx-server/uv.lock rather
      # than nixpkgs' own source, so the release the worker runs is the one
      # Renovate tracks. nixpkgs' check phase is kept.
      mlx-lm = super.mlx-lm.overridePythonAttrs (old: {
        version = versions.mlxLm;
        src = pkgs.fetchurl (uvLock.sdist "mlx-lm");
        # The sdist declares setuptools-scm as a build requirement (0.32.0+).
        build-system = (old.build-system or [ ]) ++ [ super.setuptools-scm ];
      });

      # lm-eval is a test input of mlx-lm; accelerate and peft are test inputs
      # of lm-eval only, never in the served env. They come from nixpkgs'
      # unmodified set so their store paths are the ones cache.nixos.org
      # already built and tested.
      lm-eval = super.lm-eval.overridePythonAttrs (old: {
        nativeCheckInputs = map (
          p:
          if
            lib.elem (p.pname or "") [
              "accelerate"
              "peft"
            ]
          then
            py.pkgs.${p.pname}
          else
            p
        ) old.nativeCheckInputs;
      });
    };
}
