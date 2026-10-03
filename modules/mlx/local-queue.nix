# programs.mlx.localQueue — HAProxy on loopback in front of llama-swap, plus
# the power agent its agent-check reads. Config: ./local-queue-cfg.nix.
{
  config,
  lib,
  pkgs,
  mlxShared,
  ...
}:
let
  cfg = config.programs.mlx;
  qcfg = cfg.localQueue;
  inherit (cfg) roleMap;
  rendered = import ./local-queue-cfg.nix {
    inherit roleMap;
    inherit (qcfg) hostClass;
    upstreamPort = cfg.port;
  };
  logDir = "${config.home.homeDirectory}/Library/Logs/mlx-local-queue";
  host = roleMap.hosts.${qcfg.hostClass};
in
{
  options.programs.mlx.localQueue = {
    enable = lib.mkEnableOption "the loopback HAProxy queue front (wait and direct classes, Prometheus metrics, power gating)";
    hostClass = lib.mkOption {
      type = lib.types.enum (builtins.attrNames cfg.roleMap.hosts);
      description = "Role-map host class whose resident and swap models get a backend each.";
    };
  };

  config = lib.mkIf (cfg.enable && qcfg.enable) {
    # HAProxy admits a model's role-map concurrency; llama-swap must admit the
    # same, or the wait class turns into llama-swap 429s.
    assertions = map (key: {
      assertion =
        mlxShared.effectiveConcurrency roleMap.models.${key}.id == roleMap.models.${key}.concurrency;
      message = "programs.mlx.localQueue: llama-swap concurrency for `${key}` differs from the role map's ${
        toString roleMap.models.${key}.concurrency
      }.";
    }) (host.resident ++ host.swap);

    launchd.agents = {
      mlx-local-queue = {
        enable = true;
        config = {
          Label = "dev.mlx-local-queue";
          ProgramArguments = [
            (lib.getExe pkgs.haproxy)
            "-db"
            "-f"
            "${pkgs.writeText "haproxy.cfg" rendered.text}"
          ];
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 10;
          StandardOutPath = "${logDir}/haproxy.log";
          StandardErrorPath = "${logDir}/haproxy.error.log";
        };
      };

      # Answers HAProxy's agent-check: `up ready` on AC power (`up` returns the
      # server to service, `ready` lifts maintenance), `maint` on battery.
      # launchd owns the socket and runs the line once per connection
      # (inetd-style), so there is no daemon and no script file.
      mlx-power-agent = {
        enable = true;
        config = {
          Label = "dev.mlx-power-agent";
          ProgramArguments = [
            "/bin/sh"
            "-c"
            "/usr/bin/pmset -g ps | /usr/bin/grep -q 'AC Power' && echo up ready || echo maint"
          ];
          inetdCompatibility.Wait = false;
          Sockets.agent = {
            SockNodeName = "127.0.0.1";
            SockServiceName = toString rendered.ports.powerAgent;
            SockType = "stream";
            SockFamily = "IPv4";
          };
        };
      };
    };
  };
}
