# Official mlx_lm.server wrappers carrying the in-process L2 memory limit.
# Split from default.nix for the 12 KB file-size gate. The release wrapper is
# Nix-store backed; the pinned git wrapper remains isolated to DeepSeek-V4.
{
  pkgs,
  lib,
  cfg,
  versions,
  uvPythonVersion,
  mlxPin,
  transformersPin,
  mlxLmGit,
}:
let
  gib = 1024 * 1024 * 1024;

  # mlx (Metal wheel) + harmony-patched release mlx-lm, one atomic set.
  pythonEnv = (import ./python-overlay.nix { inherit pkgs versions; }).withPackages (ps: [
    ps.mlx-lm
  ]);
  launcher = ./scripts/mlx-lm-launch.py;
  mlxLmGitWheel = import ./mlx-lm-git.nix { inherit pkgs mlxLmGit; };
in
{
  pkg = pkgs.writeShellApplication {
    name = "mlx-lm-server";
    text = builtins.readFile (
      pkgs.replaceVars ./scripts/mlx-lm-server.sh {
        memoryLimitBytes = toString (cfg.memoryHardLimitGb * gib);
        cacheLimitBytes =
          if cfg.bufferCacheLimitGb == null then "" else toString (cfg.bufferCacheLimitGb * gib);
        suppressWiredLimit = if cfg.suppressWiredLimit then "1" else "";
        pythonEnv = "${pythonEnv}";
        launcher = "${launcher}";
      }
    );
  };

  # The upstream git pin supplies DeepSeek-V4 before a release does. Keep it
  # distinct from the harmony-patched release wrapper: it does not support the
  # release-only harmony parser flag, and catalog assertions constrain use.
  gitPkg = pkgs.writeShellScriptBin "mlx-lm-server-git" ''
    export MLX_L1_MEMORY_LIMIT_BYTES=${toString (cfg.memoryHardLimitGb * gib)}
    ${lib.optionalString (cfg.bufferCacheLimitGb != null)
      "export MLX_L1_CACHE_LIMIT_BYTES=${toString (cfg.bufferCacheLimitGb * gib)}"
    }
    ${lib.optionalString cfg.suppressWiredLimit "export MLX_SUPPRESS_WIRED_LIMIT=1"}
    exec ${pkgs.uv}/bin/uv run --python ${uvPythonVersion} --with "${mlxLmGitWheel}" --with "${mlxPin}" --with "${transformersPin}" python ${launcher} "$@"
  '';

  # Both wrappers exec the same launcher, so one derived process pattern covers
  # release and git-pinned workers.
  launchScriptBasename = builtins.baseNameOf (toString launcher);
}
