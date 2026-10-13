{
  pkgs,
  src,
  hmConfig,
}:
let
  cfg = hmConfig.config;
  claudeStart = cfg.programs.claude.settings.hooks.SubagentStart or [ ];
  codexStart = cfg.programs.codex.hooks.events.SubagentStart or [ ];
  hasRoutingHook =
    entries:
    builtins.any (
      entry:
      entry.matcher == "*"
      && builtins.any (
        hook: hook.type == "command" && builtins.match ".*agent-routing-context.*" hook.command != null
      ) entry.hooks
    ) entries;
  hasPackage = name: builtins.any (package: pkgs.lib.getName package == name) cfg.home.packages;
in
{
  agent-routing-hooks =
    assert
      hasRoutingHook claudeStart
      || throw "Claude SubagentStart hook was not rendered: ${builtins.toJSON claudeStart}";
    assert
      hasRoutingHook codexStart
      || throw "Codex SubagentStart hook was not rendered: ${builtins.toJSON codexStart}";
    assert hasPackage "agent-routing-context";
    assert hasPackage "agent-spawn-gate";
    pkgs.runCommand "check-agent-routing-hooks" { } ''
      touch $out
    '';

  agent-route =
    pkgs.runCommand "check-agent-route"
      {
        SRC = src;
        nativeBuildInputs = with pkgs; [
          bash
          curl
          jq
          coreutils
          git
          gnused
          shellcheck
        ];
      }
      ''
        shellcheck --severity=warning --exclude=SC1091 \
          ${src}/modules/agent-hooks/agent-route.sh \
          ${src}/modules/agent-hooks/zai-quota.sh \
          ${src}/modules/agent-hooks/agent-spawn-gate.sh \
          ${src}/modules/agent-hooks/agent-routing-context.sh \
          ${src}/lib/checks/scripts/agent-route-test.sh \
          ${src}/lib/checks/scripts/zai-quota-test.sh \
          ${src}/lib/checks/scripts/agent-spawn-gate-test.sh \
          ${src}/lib/checks/scripts/agent-routing-context-test.sh
        bash ${src}/lib/checks/scripts/agent-route-test.sh
        bash ${src}/lib/checks/scripts/zai-quota-test.sh
        bash ${src}/lib/checks/scripts/agent-spawn-gate-test.sh
        bash ${src}/lib/checks/scripts/agent-routing-context-test.sh
        touch $out
      '';
}
