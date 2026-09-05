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
  # an entry for an event that also has a typed hook would drop it. Rebuild the
  # typed entries from that flake's own mapping and append herdr's, keeping
  # both. Importing the mapping rather than restating it is what keeps this
  # correct when upstream adds an event.
  hookEventMapping = import "${nix-claude-code}/lib/hook-event-mapping.nix";

  typedClaudeHooks = lib.mapAttrs' (
    _hookName: mapping:
    lib.nameValuePair mapping.claudeEvent [
      {
        matcher = "";
        hooks = [
          {
            type = "command";
            command = "${homeDir}/.claude/hooks/${mapping.fileName}";
          }
        ];
      }
    ]
  ) (lib.filterAttrs (hookName: _: (claudeCfg.hooks.${hookName} or null) != null) hookEventMapping);

  herdrClaudeHooks.SessionStart = [
    {
      matcher = "*";
      hooks = [ (hookEntry claudeHookPath) ];
    }
  ];

  codexHooksJson = pkgs.writers.writeJSON "herdr-codex-hooks.json" {
    hooks.SessionStart = [ { hooks = [ (hookEntry codexHookPath) ]; } ];
  };

  opencodeTuiConfig = pkgs.writers.writeJSON "herdr-opencode-tui.jsonc" {
    plugin = [ "./herdr-tui-session.js" ];
  };
in
{
  config = lib.mkIf (cfg.enable && cfg.package != null && cfg.integrations != [ ]) (
    lib.mkMerge [
      {
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
            ".codex/hooks.json".source = codexHooksJson;
          })
          (lib.mkIf (wanted "opencode") {
            "${opencodeDir}/plugins/herdr-agent-state.js".source = "${payloads}/opencode/herdr-agent-state.js";
            "${opencodeDir}/herdr-tui-session.js".source = "${payloads}/opencode/herdr-tui-session.js";
            "${opencodeDir}/tui.jsonc".source = opencodeTuiConfig;
          })
        ];
      }

      # `settings` is a freeform attrs submodule: a `lib.mkIf` on the VALUE is
      # never resolved and reaches settings.json as a literal `_type = "if"`
      # attrset. Wrapping the definition works, because the module system
      # resolves that before the freeform value is read. `optionalAttrs` here
      # would decide the config's shape from config itself, which recurses.
      (lib.mkIf (wanted "claude") {
        programs.claude.settings.hooks = lib.zipAttrsWith (_event: lib.concatLists) [
          typedClaudeHooks
          herdrClaudeHooks
        ];
      })

      # Codex reads hooks.json only when this feature flag is on.
      (lib.mkIf (wanted "codex") {
        programs.codex.features.hooks = true;
      })
    ]
  );
}
