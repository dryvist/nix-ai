#
# MLX Module — Periodic Orphan-Reap LaunchAgent
#
# Split from launchd.nix: the timer that reclaims worker ports and memory held
# by processes re-parented to launchd (see modules/mlx/scripts/mlx-orphan-reap.sh).
#
{
  config,
  lib,
  pkgs,
  mlxShared,
  ...
}:
let
  inherit (mlxShared)
    cfg
    llamaSwapConfigAttrs
    allModels
    ;

  # Sole consumer, so the derivation lives with the agent that runs it rather
  # than in default.nix's shared let (which is at the 12KB file-size gate).
  mlxOrphanReapPkg = import ./mlx-orphan-reap-pkg.nix { inherit pkgs lib; };

  # Worker ports llama-swap could hand out to a model in the CURRENT config —
  # an overestimate is safe (a few extra ports get scanned and come back
  # empty), an underestimate would not be. Same derivation launchd.nix uses.
  workerPortCount = builtins.length (builtins.attrNames allModels);

  # Orphan-reap cadence. An orphan wastes memory, never correctness, so this is
  # deliberately slack: the launcher's own reap still covers every restart, and
  # this only backstops the case where no restart comes. 300s bounds the waste
  # to minutes without adding a per-minute lsof sweep across the port block.
  orphanReapIntervalSeconds = 300;
in
{
  config = lib.mkIf cfg.enable {
    # The launcher's reap is start-triggered, so an orphan persists across an
    # unbounded gap whenever the proxy never comes back (bootout, KeepAlive
    # off, perf-reclaim). Measured 2026-07-26: a 16.7 GB orphan held a worker
    # port 94 minutes. The serving watchdog's reap_workers never loads on an
    # mlx-lm host, so this is the only reclaim path independent of a proxy
    # start. Reaps ONLY launchd-re-parented holders (ppid 1), never the live
    # worker. Rationale: scripts/mlx-orphan-reap.sh.
    launchd.agents.mlx-orphan-reap = {
      enable = true;
      config = {
        Label = "dev.mlx-model-server.orphan-reap";
        ProgramArguments = [ (lib.getExe mlxOrphanReapPkg) ];
        RunAtLoad = false;
        StartInterval = orphanReapIntervalSeconds;
        ProcessType = "Background";
        EnvironmentVariables = {
          # Same port block the launcher protects, same sources.
          MLX_PORT = toString cfg.port;
          MLX_WORKER_PORT_RANGE_START = toString llamaSwapConfigAttrs.startPort;
          MLX_WORKER_PORT_COUNT = toString workerPortCount;
        };
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/mlx-model-server/orphan-reap.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/mlx-model-server/orphan-reap.error.log";
      };
    };
  };
}
