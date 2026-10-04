{
  config,
  lib,
  pkgs,
  nix-claude-code,
  nix-codex,
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
  packages = lib.mapAttrsToList (
    name: tool:
    tool.renderer {
      inherit pkgs;
      nofile = agentNofile;
      executable =
        if (tool.cfg.package or null) != null then
          "${tool.cfg.package}/bin/${name}"
        else
          "/opt/homebrew/bin/${name}";
    }
  ) enabled;
  launchers = pkgs.symlinkJoin {
    name = "agent-cli-launchers";
    paths = packages;
    passthru.launchers = packages;
  };
in
{
  config = lib.mkIf (packages != [ ]) {
    home.packages = [ (lib.hiPrio launchers) ];
    home.sessionPath = [ "${launchers}/bin" ];
    programs.zsh.initContent = lib.mkAfter ''
      export PATH=${lib.escapeShellArg "${launchers}/bin"}:"$PATH"
    '';
  };
}
