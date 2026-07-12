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
  inherit (mlxShared) cfg;
  ncfg = cfg.clusterMode;
  versions = import ../../lib/versions.nix;
  logDir = "${config.home.homeDirectory}/Library/Logs/mlx-cluster";
in
{
  config = lib.mkIf (cfg.enable && ncfg.enable) {
    launchd.agents =
      lib.optionalAttrs ncfg.prefetch {
        # One-shot idempotent prefetch; KeepAlive-until-success retries partial
        # downloads (198 GB) across failures, throttled by launchd.
        mlx-cluster-prefetch = {
          enable = true;
          config = {
            Label = "dev.mlx-cluster.prefetch";
            ProgramArguments = [
              "${pkgs.uv}/bin/uvx"
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
      }
      // {
        # Bounded cluster logs, rotated hourly (offset from the normal-mode rotation).
        mlx-cluster-logrotate = {
          enable = true;
          config = {
            Label = "dev.mlx-cluster.logrotate";
            ProgramArguments = [
              "/usr/sbin/newsyslog"
              "-f"
              "${config.home.homeDirectory}/.config/newsyslog.d/mlx-cluster.conf"
            ];
            StartCalendarInterval = [ { Minute = 30; } ];
          };
        };
      };

    # newsyslog config consumed by mlx-cluster-logrotate (same pattern as the
    # normal-mode server's vllm-mlx.conf).
    home.file.".config/newsyslog.d/mlx-cluster.conf".text = ''
      # logfilename                                  [owner:group]  mode  count  size  when  flags
      ${logDir}/cluster-rank.log                       :              644   3      10240 *     J
      ${logDir}/cluster-rank.error.log                 :              644   3      10240 *     J
      ${logDir}/cluster-watcher.log                    :              644   3      10240 *     J
      ${logDir}/cluster-watcher.error.log              :              644   3      10240 *     J
      ${logDir}/cluster-prefetch.log                   :              644   3      10240 *     J
      ${logDir}/cluster-prefetch.error.log             :              644   3      10240 *     J
    '';
  };
}
