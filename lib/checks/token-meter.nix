# token-meter module regression tests
#
# The gate agent is the only load-bearing output: it must reach token-meter's
# hardcoded loopback port and must never appear when the module is disabled.
{
  pkgs,
  hmConfig,
  hmConfigTokenMeter,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  token-meter-gate =
    let
      cfg = hmConfigTokenMeter.config.programs.token-meter;
      agent = hmConfigTokenMeter.config.launchd.agents.token-meter-gate.config;
      args = agent.ProgramArguments;
      # Store paths are computed during evaluation, so comparing them asserts
      # the rendered Caddyfile byte-for-byte without building it (no IFD).
      expected = pkgs.writeText "token-meter-Caddyfile" ''
        ${cfg.bindAddress}:${toString cfg.gatePort} {
          bind ${cfg.bindAddress}
          tls internal
          reverse_proxy 127.0.0.1:8722
        }
      '';
    in
    assert
      builtins.elem "run" args
      || throw "token-meter gate must run caddy: ${builtins.concatStringsSep " " args}";
    assert
      builtins.elemAt args 3 == "${expected}"
      || throw "token-meter Caddyfile drifted from ${cfg.bindAddress}:${toString cfg.gatePort} -> 127.0.0.1:8722";
    assert (agent.KeepAlive or false) || throw "token-meter gate must have KeepAlive = true";
    helpers.mkMarker "check-token-meter-gate" "token-meter gate: ${cfg.bindAddress}:${toString cfg.gatePort} -> 127.0.0.1:8722 verified";

  token-meter-gate-negative =
    assert
      !(hmConfig.config.launchd.agents ? token-meter-gate)
      || throw "token-meter gate must NOT be defined when programs.token-meter.enable = false (default)";
    helpers.mkMarker "check-token-meter-gate-negative" "token-meter gate correctly absent when disabled";
}
