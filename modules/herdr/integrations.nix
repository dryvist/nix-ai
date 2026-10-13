#
# herdr Module — agent lifecycle integrations
#
# Without these hooks herdr infers pane state from terminal heuristics; with
# them each agent reports its own session id and working/blocked/idle
# transitions over the control socket.
#
# The payloads ship in the package under share/herdr/integrations/<agent>/ and
# are referenced from there, so they move with the pinned herdr version and no
# copy is kept in this repo. `herdr integration install` writes the same files
# into each agent's config directory, which home-manager renders read-only —
# the write fails, or the next switch reverts it. Naming the agent in
# `programs.herdr.integrations` is the declarative equivalent.
#
{
  config,
  lib,
  pkgs,
  nix-claude-code,
  ...
}:

let
  cfg = config.programs.herdr;
  homeDir = config.home.homeDirectory;
  claudeCfg = config.programs.claude;
  routingContextCfg = config.programs.agentHooks.subagentRoutingContext;
  herdrEnabled = cfg.enable && cfg.package != null && cfg.integrations != [ ];

  wanted = target: lib.elem target cfg.integrations;
  payloads = "${cfg.package}/share/herdr/integrations";

  claudeHookPath = "${homeDir}/.claude/hooks/herdr-agent-state.sh";
  codexHookPath = "${homeDir}/.codex/herdr-agent-state.sh";
  opencodeDir = config.programs.opencode.configDir or ".config/opencode";

  hookEntry = path: {
    type = "command";
    command = "bash '${path}' session";
    timeout = 10;
  };

  # nix-claude-code merges `settings.hooks` over its typed hooks with `//`, so
  # an entry for an event that also has a typed hook would drop it. Take the
  # typed entries from that flake's own renderer and combine every contributor
  # before writing the freeform settings attribute.
  typedClaudeHooks = import "${nix-claude-code}/lib/typed-hooks.nix" {
    inherit lib;
    cfg = claudeCfg;
  };

  herdrClaudeHooks = lib.optionalAttrs (herdrEnabled && wanted "claude") {
    SessionStart = [
      {
        matcher = "*";
        hooks = [ (hookEntry claudeHookPath) ];
      }
    ];
  };

  routingContextClaudeHooks = lib.optionalAttrs routingContextCfg.enable {
    SubagentStart = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = routingContextCfg.command;
            timeout = 30;
          }
        ];
      }
    ];
  };

  claudeHooks = lib.zipAttrsWith (_event: lib.concatLists) [
    typedClaudeHooks
    herdrClaudeHooks
    routingContextClaudeHooks
  ];

  opencodeTuiConfig = pkgs.writers.writeJSON "herdr-opencode-tui.jsonc" {
    plugin = [ "./herdr-tui-session.js" ];
  };
in
{
  config = lib.mkMerge [
    (lib.mkIf herdrEnabled {
      home.file = lib.mkMerge [
        (lib.mkIf (wanted "claude") {
          ".claude/hooks/herdr-agent-state.sh" = {
            source = "${payloads}/claude/herdr-agent-state.sh";
            executable = true;
          };
        })
        (lib.mkIf (wanted "codex") {
          ".codex/herdr-agent-state.sh" = {
            source = "${payloads}/codex/herdr-agent-state.sh";
            executable = true;
          };
        })
        (lib.mkIf (wanted "opencode") {
          "${opencodeDir}/plugins/herdr-agent-state.js".source = "${payloads}/opencode/herdr-agent-state.js";
          "${opencodeDir}/herdr-tui-session.js".source = "${payloads}/opencode/herdr-tui-session.js";
          "${opencodeDir}/tui.jsonc".source = opencodeTuiConfig;
        })
      ];
    })

    # `settings` is a freeform attrs submodule. Combine every event before
    # defining it so the routing context keeps herdr and typed hooks intact.
    (lib.mkIf (claudeCfg.enable && (herdrEnabled && wanted "claude" || routingContextCfg.enable)) {
      programs.claude.settings.hooks = claudeHooks;
    })

    # Codex hooks use the single hooks.json renderer in modules/codex/settings.nix.
    (lib.mkIf (herdrEnabled && wanted "codex") {
      programs.codex.hooks.events.SessionStart = [ { hooks = [ (hookEntry codexHookPath) ]; } ];
    })
  ];
}
