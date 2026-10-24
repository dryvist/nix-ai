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
  executableFor =
    name: tool:
    if (tool.cfg.package or null) != null then
      "${tool.cfg.package}/bin/${name}"
    else
      "/opt/homebrew/bin/${name}";
  packages = lib.mapAttrsToList (
    name: tool:
    tool.renderer {
      inherit pkgs;
      nofile = agentNofile;
      executable = executableFor name tool;
    }
  ) enabled;
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
    passthru.launchers = packages;
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
