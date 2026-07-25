#
# MLX Module — Clustered-mode maintenance (model prefetch + log rotation)
#
# Companion to ./cluster-mode.nix: the agents that keep clustered mode ready
# without being part of the serve path — idempotent model prefetch and
# bounded log rotation.
#
{
  config,
  lib,
  pkgs,
  mlxShared,
  ...
}:
let
  inherit (mlxShared) cfg uvPythonVersion;
  ncfg = cfg.clusterMode;
  versions = import ../../lib/versions.nix;
  logDir = "${config.home.homeDirectory}/Library/Logs/mlx-cluster";
in
{
  config = lib.mkIf (cfg.enable && ncfg.enable) {
    launchd.agents = lib.optionalAttrs ncfg.prefetch {
      # One-shot idempotent prefetch; KeepAlive-until-success retries partial
      # downloads (198 GB) across failures, throttled by launchd.
      mlx-cluster-prefetch = {
        enable = true;
        config = {
          Label = "dev.mlx-cluster.prefetch";
          ProgramArguments = [
            "${pkgs.uv}/bin/uvx"
            # Single-source CPython pin (see modules/mlx/default.nix).
            "--python"
            uvPythonVersion
            "--from"
            "huggingface-hub==${versions.huggingfaceHub}"
            "hf"
            "download"
            ncfg.model
          ];
          RunAtLoad = true;
          KeepAlive = {
            SuccessfulExit = false;
          };
          ThrottleInterval = 300;
          ProcessType = "Background";
          EnvironmentVariables = {
            HF_HOME = cfg.huggingFaceHome;
          };
          StandardOutPath = "${logDir}/cluster-prefetch.log";
          StandardErrorPath = "${logDir}/cluster-prefetch.error.log";
        };
      };
    };

    # Rotation for ~/Library/Logs/mlx-cluster lives in nix-darwin's
    # programs.agent-log-rotation, run by the system newsyslog as root. The user
    # LaunchAgent that used to be here could never work: newsyslog refuses to
    # run as anyone but root.
  };
}
