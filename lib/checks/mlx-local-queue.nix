# programs.mlx.localQueue (modules/mlx/local-queue*.nix).
#
#   mlx-local-queue-maxconn  every rendered backend's maxconn is the role map's
#                            concurrency for that model; a map with a bumped
#                            concurrency renders the bumped value and is
#                            reported against the real map. The module is off
#                            by default; enabled, it asserts llama-swap admits
#                            the same concurrency and reports a host that
#                            does not.
#   mlx-local-queue-config   `haproxy -c` (warnings fatal) accepts the config
#                            rendered for every host class, and rejects a
#                            config with an unknown keyword.
#   mlx-local-queue-agent-recovery
#                            HAProxy, started on the rendered config with the
#                            module's own power-agent command answering each
#                            probe, takes every server UP -> MAINT (battery)
#                            -> UP (AC). The same cycle against an agent that
#                            replies a bare `ready` must fail.
{
  pkgs,
  roleMap,
  hmConfig,
  mkHmConfig,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };
  render =
    candidate: hostClass:
    (import ../../modules/mlx/local-queue-cfg.nix {
      roleMap = candidate;
      inherit hostClass;
      upstreamPort = 11434;
    }).text;
  classes = builtins.attrNames roleMap.hosts;

  # backend name -> maxconn, read back from the rendered text.
  maxconns =
    text:
    lib.listToAttrs (
      lib.concatMap (
        line:
        let
          m = builtins.match " *server ([^ ]+) [^ ]+ maxconn ([0-9]+) .*" line;
        in
        lib.optional (m != null) (lib.nameValuePair (builtins.head m) (lib.toInt (lib.last m)))
      ) (lib.splitString "\n" text)
    );
  errors =
    text: hostClass:
    let
      host = roleMap.hosts.${hostClass};
      got = maxconns text;
    in
    lib.filter (key: (got.${key} or null) != roleMap.models.${key}.concurrency) (
      host.resident ++ host.swap
    );

  bumped = roleMap // {
    models = roleMap.models // {
      mimo-9b = roleMap.models.mimo-9b // {
        concurrency = roleMap.models.mimo-9b.concurrency + 1;
      };
    };
  };

  enabledWith =
    extra:
    mkHmConfig [
      {
        programs.mlx.localQueue = {
          enable = true;
          hostClass = "server";
        };
      }
      extra
    ];
  catalog = {
    programs.mlx.catalog = {
      qwen38-27b.class = "resident";
      mimo-9b.class = "resident";
      unlimited-ocr.class = "swap";
    };
  };
  # home-manager throws on any failed assertion the moment `config` is
  # touched, so the negative case is a tryEval; the catalog case is its
  # positive control (same fixture, one variable).
  evaluates = extra: (builtins.tryEval (enabledWith extra).config.launchd.agents).success;
  agents = (enabledWith catalog).config.launchd.agents;

  # Agent-recovery fixture: the rendered config probing every second instead of
  # every 30s, and the launchd agent's command with its macOS-only pieces
  # swapped for a power state held in $PMSET_STATE (grep is the sandbox's).
  rendered = import ../../modules/mlx/local-queue-cfg.nix {
    inherit roleMap;
    hostClass = "server";
    upstreamPort = 11434;
  };
  fastCfg = pkgs.writeText "haproxy-fast-probe.cfg" (
    builtins.replaceStrings [ "agent-inter 30s" ] [ "agent-inter 1s" ] rendered.text
  );
  agentScript =
    command:
    pkgs.writeText "power-agent.sh" (
      builtins.replaceStrings [ "/usr/bin/pmset -g ps" "/usr/bin/grep" ] [ "cat \"$PMSET_STATE\"" "grep" ]
        command
    );
  liveAgent = agentScript (lib.last agents.mlx-power-agent.config.ProgramArguments);
  # The reply before the fix: `ready` lifts maintenance but never sets UP.
  bareReadyAgent = agentScript "/usr/bin/pmset -g ps | /usr/bin/grep -q 'AC Power' && echo ready || echo maint";
in
{
  mlx-local-queue-maxconn =
    assert
      lib.all (c: errors (render roleMap c) c == [ ]) classes
      || throw "local queue: a rendered maxconn differs from the role map's concurrency";
    assert
      (maxconns (render bumped "server")).mimo-9b == bumped.models.mimo-9b.concurrency
      && errors (render bumped "server") "server" == [ "mimo-9b" ]
      || throw "local queue: maxconn must track the role map, and a mismatch must be reported";
    assert
      !(hmConfig.config.launchd.agents ? mlx-local-queue) || throw "local queue: must be off by default";
    assert
      agents.mlx-local-queue.enable
      && agents.mlx-power-agent.config.inetdCompatibility.Wait == false
      && evaluates catalog
      || throw "local queue: enabled with a matching catalog, both agents exist and no assertion fires";
    assert
      !(evaluates { })
      || throw "local queue: llama-swap concurrency below the role map's must be reported";
    helpers.mkMarker "check-mlx-local-queue-maxconn" "local queue: maxconn equals role-map concurrency; mismatches reported";

  mlx-local-queue-config =
    pkgs.runCommand "check-mlx-local-queue-config" { nativeBuildInputs = [ pkgs.haproxy ]; }
      ''
        ${lib.concatMapStrings (c: ''
          haproxy -c -dW -f ${pkgs.writeText "haproxy-${c}.cfg" (render roleMap c)}
        '') classes}
        if haproxy -c -dW -f ${
          pkgs.writeText "haproxy-bad.cfg" (render roleMap "server" + "\nnot-a-keyword\n")
        }; then
          echo "haproxy -c accepted an unknown keyword; the check proves nothing" >&2
          exit 1
        fi
        touch $out
      '';

  mlx-local-queue-agent-recovery = pkgs.runCommand "check-mlx-local-queue-agent-recovery" {
    nativeBuildInputs = [
      pkgs.haproxy
      pkgs.socat
      pkgs.curl
    ];
    HAPROXY_CFG = fastCfg;
    AGENT_PORT = toString rendered.ports.powerAgent;
    METRICS_URL = (import ../../vars/ai-stack.nix).endpoints.mlx_metrics;
    LIVE_AGENT = liveAgent;
    BARE_READY_AGENT = bareReadyAgent;
  } "bash ${./scripts/mlx-local-queue-agent-recovery.sh}";
}
