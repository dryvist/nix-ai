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
# Everything above mlx (mlx-lm, transformers, tokenizers) comes from nixpkgs
# unchanged; packageOverrides makes mlx-lm rebuild against the wheel mlx.
#
# ATOMICITY
#
# mlx / mlx-lm / transformers are ONE set — see lib/python.nix. Expressing them
# in a single overlay makes a partial bump unrepresentable, rather than merely
# prohibited by a Renovate exclusion that a config edit could get wrong. The
# two cluster nodes must resolve identical builds or ranks fail to rendezvous.
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
  };
}
