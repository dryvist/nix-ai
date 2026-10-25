{
  config,
  lib,
  pkgs,
  nix-claude-code-launcher-src,
  nix-codex-launcher-src,
  nix-agy,
  agentNofile,
  ...
}:
let
  tools = {
    claude = {
      renderer = import "${nix-claude-code-launcher-src}/lib/mk-launcher.nix";
      cfg = config.programs.claude or { };
    };
    codex = {
      renderer = import "${nix-codex-launcher-src}/lib/mk-launcher.nix";
      cfg = config.programs.codex or { };
    };
    agy = {
      renderer = nix-agy.lib.mkLauncher;
      cfg = config.programs.antigravity-cli or { };
    };
  };
  enabled = lib.filterAttrs (_: tool: tool.cfg.enable or false) tools;
  mcpClient = import ./mcp/client.nix { inherit lib; };
  executableFor =
    name: tool:
    if (tool.cfg.package or null) != null then
      "${tool.cfg.package}/bin/${name}"
    else
      "/opt/homebrew/bin/${name}";
  # Null unless the host set programs.aiMcp.gatewayKeyLaunchPrefixFor and the
  # harness has a caller ID; the env name comes from modules/mcp/client.nix.
  gatewayFor =
    tool:
    let
      callerId = tool.cfg.callerId or null;
      hook = config.programs.aiMcp.gatewayKeyLaunchPrefixFor;
    in
    if hook == null || callerId == null then
      null
    else
      let
        env = mcpClient.keyEnvFor callerId (tool.cfg.callerKeyEnv or null);
      in
      {
        inherit callerId env;
        prefix = hook { inherit callerId env; };
      };
  # The claude launcher also runs for claude-zai, which sets
  # AGENT_GATEWAY_CALLER=claude-zai and fetches its own key. Consuming the
  # marker here keeps the claude-code key out and stops it reaching the process.
  gatewayWrapperFor =
    name: target: gateway:
    pkgs.writeShellScript "${name}-gateway-launcher" ''
      ${lib.optionalString (name == "claude") ''
        if [ "''${AGENT_GATEWAY_CALLER:-}" = ${lib.escapeShellArg "claude-zai"} ]; then
          unset AGENT_GATEWAY_CALLER
          exec ${lib.escapeShellArg target} "$@"
        fi
      ''}
      if [ -n "''${${gateway.env}:-}" ]; then
        exec ${lib.escapeShellArg target} "$@"
      fi
      exec ${lib.escapeShellArgs gateway.prefix} ${lib.escapeShellArg target} "$@"
    '';
  rendered = lib.mapAttrs (
    name: tool:
    let
      target = executableFor name tool;
      gateway = gatewayFor tool;
      wrapper = if gateway == null then null else gatewayWrapperFor name target gateway;
    in
    {
      package = tool.renderer {
        inherit pkgs;
        nofile = agentNofile;
        executable = if wrapper == null then target else "${wrapper}";
      };
      inherit wrapper;
    }
  ) enabled;
  packages = lib.mapAttrsToList (_: value: value.package) rendered;
  gatewayWrappers = lib.filterAttrs (_: wrapper: wrapper != null) (
    lib.mapAttrs (_: value: value.wrapper) rendered
  );
  checkTargets = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: tool:
      let
        target = executableFor name tool;
        message = "WARNING: agent launcher '${name}' target is missing or not executable: ${target}";
      in
      ''
        if [ ! -x ${lib.escapeShellArg target} ]; then
          # Warn rather than abort: a failed activation mid-switch leaves a half-applied generation.
          printf '%s\n' ${lib.escapeShellArg message} >&2
        fi
      ''
    ) enabled
  );
  launchers = pkgs.symlinkJoin {
    name = "agent-cli-launchers";
    paths = packages;
    passthru = {
      launchers = packages;
      inherit gatewayWrappers;
    };
  };
in
{
  config = lib.mkIf (packages != [ ]) {
    home = {
      packages = [ (lib.hiPrio launchers) ];
      sessionPath = [ "${launchers}/bin" ];
      activation.agentLauncherTargets = lib.hm.dag.entryAfter [ "writeBoundary" ] checkTargets;
    };

    programs.zsh.initContent = lib.mkAfter ''
      export PATH=${lib.escapeShellArg "${launchers}/bin"}:"$PATH"
    '';
  };
}
