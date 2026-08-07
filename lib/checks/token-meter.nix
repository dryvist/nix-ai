# token-meter module regression tests
#
# The gate agent is the only load-bearing output: it must reach token-meter's
# dashboard port and must never appear when the module is disabled.
{
  pkgs,
  src,
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
      # Restated rather than imported on purpose: this is the drift detector,
      # so it must fail when the module's Caddyfile changes without the change
      # being made here too. The global block is part of that — dropping
      # `auto_https disable_redirects` makes Caddy open a port-80 listener it
      # cannot bind as a user agent, which takes the whole gate down.
      expected = pkgs.writeText "token-meter-Caddyfile" ''
        {
        	auto_https disable_redirects
        }

        ${cfg.bindAddress}:${toString cfg.gatePort} {
        	bind ${cfg.bindAddress}
        	tls internal
        	reverse_proxy 127.0.0.1:${toString cfg.dashboardPort}
        }
      '';
      route = "${cfg.bindAddress}:${toString cfg.gatePort} -> 127.0.0.1:${toString cfg.dashboardPort}";
    in
    assert
      builtins.elem "run" args
      || throw "token-meter gate must run caddy: ${builtins.concatStringsSep " " args}";
    assert
      builtins.elemAt args 3 == "${expected}" || throw "token-meter Caddyfile drifted from ${route}";
    assert (agent.KeepAlive or false) || throw "token-meter gate must have KeepAlive = true";
    # A host with the gate on also runs the llm-gate Caddy. On default paths the
    # two share one data directory, so losing this isolation means two Caddies
    # contending over a single local CA, instance id, and lock set.
    assert
      (agent.EnvironmentVariables.XDG_DATA_HOME or "") != ""
      && (agent.EnvironmentVariables.XDG_CONFIG_HOME or "") != ""
      || throw "token-meter gate must set XDG_DATA_HOME and XDG_CONFIG_HOME so its Caddy storage stays separate from llm-gate's";
    helpers.mkMarker "check-token-meter-gate" "token-meter gate: ${route} verified";

  token-meter-gate-negative =
    assert
      !(hmConfig.config.launchd.agents ? token-meter-gate)
      || throw "token-meter gate must NOT be defined when programs.token-meter.enable = false (default)";
    helpers.mkMarker "check-token-meter-gate-negative" "token-meter gate correctly absent when disabled";

  # token-meter labels every answer with the runtime that asked, so each client
  # must render its own name — the one value the shared catalog cannot hold.
  # Only Claude's rendered servers are reachable as an option; every other
  # client folds its MCP block into an internal configAttrs, so their wiring is
  # asserted at the call site instead — the same split as
  # mlx-cluster-pd-callsites.nix. A seventh client added without a `client`
  # argument renders token-meter unlabelled, and no other check would catch it.
  token-meter-mcp-caller =
    let
      claudeServers = hmConfigTokenMeter.config.programs.claude.mcpServers;
      # No other catalog entry sets clientNameEnv, so no other server may have
      # picked the variable up from the shared render step.
      leaked = builtins.attrNames (
        pkgs.lib.filterAttrs (_: server: (server.env or { }) ? TOKEN_METER_CALLER) (
          builtins.removeAttrs claudeServers [ "token-meter" ]
        )
      );
      callSites = {
        "modules/claude-config.nix" = "claude";
        "modules/codex/settings.nix" = "codex";
        "modules/qwen-code/settings.nix" = "qwen-code";
        "modules/opencode/default.nix" = "opencode";
        "modules/antigravity-cli/settings.nix" = "antigravity-cli";
        "modules/antigravity-ide/default.nix" = "antigravity-ide";
      };
      unwired = pkgs.lib.filter (
        f: !(pkgs.lib.hasInfix ''client = "${callSites.${f}}";'' (builtins.readFile (src + "/${f}")))
      ) (builtins.attrNames callSites);
    in
    assert
      (claudeServers.token-meter.env or { }) == {
        TOKEN_METER_CALLER = "claude";
      }
      || throw "token-meter must reach Claude labelled claude, got ${
        builtins.toJSON (claudeServers.token-meter.env or { })
      }";
    assert
      unwired == [ ] || throw "MCP renderers missing their client name: ${builtins.toJSON unwired}";
    assert leaked == [ ] || throw "TOKEN_METER_CALLER leaked onto: ${builtins.toJSON leaked}";
    helpers.mkMarker "check-token-meter-mcp-caller" "token-meter MCP: Claude renders TOKEN_METER_CALLER=claude and all six renderers pass their own client name";
}
