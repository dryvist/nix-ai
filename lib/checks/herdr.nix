# herdr module regression tests
#
# The coverage check is the load-bearing one. herdr classifies a pane as
# working/blocked/idle by matching manifest rules against the foreground
# process; a CLI with no manifest shows up as a bare shell, and every downstream
# consumer — blocked-agent alerting, `herdr agent wait`, the web dashboard's
# approvals — silently sees nothing to report. Adding a CLI to
# this flake without a manifest is exactly the "a newly advertised tier cannot
# go unmonitored" failure the fabric watchdog's assert exists to prevent.
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  cfg = hmConfig.config.programs.herdr;
  programs = hmConfig.config.programs;
  opencodeDir = programs.opencode.configDir or ".config/opencode";
  claudeTypedSessionStart = (programs.claude.hooks.sessionStart or null) != null;

  # Which of this flake's CLIs herdr is expected to recognise, keyed by THIS
  # flake's option name. Translation to herdr's own manifest name happens in
  # `covered` below, and only for the agentManifests branch.
  managedAgents = {
    claude = programs.claude.enable or false;
    codex = programs.codex.enable or false;
    cursor = programs.cursor.enable or false;
    opencode = programs.opencode.enable or false;
    antigravity-cli = programs.antigravity-cli.enable or false;
    qwen-code = programs.qwen-code.enable or false;
    cecli = programs.cecli.enable or false;
  };

  enabledAgents = lib.attrNames (lib.filterAttrs (_: v: v) managedAgents);

  # herdr selects a local manifest by FILENAME, and agentManifests renders
  # `<attrname>.toml`. So a manifest must be keyed by HERDR's name for the
  # agent, not by this flake's option name: `agentManifests.qwen-code` writes
  # qwen-code.toml, which herdr ignores without warning while still looking
  # like coverage here. Verified live against 0.8.2 — an identical manifest is
  # picked up as `source_kind: local override` under qwen.toml and produces no
  # local override, and no diagnostic, under any other filename.
  #
  # Only this branch needs the translation. knownUpstreamAgents is keyed by
  # option name on purpose, because it answers "is the CLI we enable detected",
  # not "what is the file called".
  herdrManifestName = {
    antigravity-cli = "agy";
    qwen-code = "qwen";
  };

  covered =
    name:
    lib.elem name cfg.knownUpstreamAgents
    || lib.hasAttr (herdrManifestName.${name} or name) cfg.agentManifests
    || lib.elem name cfg.knownUnsupportedAgents;

  uncovered = lib.filter (name: !(covered name)) enabledAgents;
in
{
  herdr-options-regression = helpers.mkOptionsRegression {
    label = "herdr";
    checkName = "check-herdr-options-regression";
    inherit cfg;
    expectedOptions = [
      "agentManifests"
      "configDir"
      "defaultRemote"
      "enable"
      "integrations"
      "knownUnsupportedAgents"
      "knownUpstreamAgents"
      "package"
      "remotes"
      "settings"
    ];
  };

  herdr-defaults-regression = helpers.mkDefaultsRegression {
    label = "herdr";
    checkName = "check-herdr-defaults-regression";
    checks = [
      {
        name = "herdr.enable";
        actual = cfg.enable;
        expected = true;
      }
      {
        name = "herdr.configDir";
        actual = cfg.configDir;
        expected = ".config/herdr";
      }
      {
        name = "herdr.package is installed (not null)";
        actual = cfg.package != null;
        expected = true;
      }
      {
        name = "herdr binary lands in home.packages";
        actual = lib.elem cfg.package hmConfig.config.home.packages;
        expected = true;
      }
    ];
  };

  # Forces the rendered config.toml and every manifest, not just their
  # attribute names — a check that reads a few attributes of a large structure
  # proves nothing about the rest (see CLAUDE.md).
  herdr-rendered-files-regression =
    let
      files = hmConfig.config.home.file;
      configPath = "${cfg.configDir}/config.toml";
      ours = lib.filterAttrs (name: _: lib.hasPrefix "${cfg.configDir}/" name) files;
    in
    assert lib.hasAttr configPath files || throw "herdr: ${configPath} is not rendered";
    # Force each rendered file's STORE PATH, not the derivation itself.
    # `deepSeq` over a derivation walks its whole attrset — drvAttrs, passthru,
    # every build input — which is both enormously slow and prone to erroring on
    # attributes that were never meant to be forced. Interpolating to a string
    # forces exactly what this check is about: that every file under configDir
    # actually renders to a path.
    assert builtins.deepSeq (lib.mapAttrsToList (_: f: "${f.source}") ours) true;
    helpers.mkMarker "check-herdr-rendered-files-regression" "herdr renders ${toString (lib.length (lib.attrNames ours))} file(s) under ${cfg.configDir}.";

  # The TUI is a client, so a module that installs the binary and renders
  # config.toml without declaring a service yields no running herd at all —
  # invisible in the rendered config and raising no error anywhere.
  herdr-launchd-regression =
    let
      agents = hmConfig.config.launchd.agents;
      absent = throw "herdr: no launchd agent is declared, so the server never runs and the herd stays empty; see modules/herdr/launchd.nix";
      agent = (agents.herdr or absent).config;
      args = agent.ProgramArguments;
      env = agent.EnvironmentVariables or { };
      expectedSocket = "${hmConfig.config.home.homeDirectory}/${cfg.configDir}/herdr.sock";
      profileBin = "/etc/profiles/per-user/${hmConfig.config.home.username}/bin";
      pathEntries = lib.splitString ":" (env.PATH or "");

      # Collected rather than asserted one at a time, so a broken agent reports
      # every fault in one pass. The last two are the silent ones: a mismatched
      # socket leaves the client hunting a socket nothing created, and a PATH
      # without the Nix profile makes every pane look like a bare shell.
      problems =
        lib.optional (
          !(lib.elem "server" args)
        ) "must run the headless server (`herdr server`), got: ${builtins.concatStringsSep " " args}"
        ++ lib.optional (!(agent.KeepAlive or false)) "must set KeepAlive = true"
        ++ lib.optional (!(agent.RunAtLoad or false)) "must set RunAtLoad = true"
        ++ lib.optional ((agent.ProcessType or "") != "Background") ''must set ProcessType = "Background"''
        ++
          lib.optional ((env.HERDR_SOCKET_PATH or null) != expectedSocket)
            "must pin HERDR_SOCKET_PATH to ${expectedSocket}, keeping the server's socket and the client's identical"
        ++ lib.optional (
          !(lib.elem profileBin pathEntries)
        ) "PATH must include ${profileBin}, leaving panes able to run claude/codex";
    in
    assert lib.assertMsg (problems == [ ]) ''
      herdr LaunchAgent is misdeclared:
      ${lib.concatMapStringsSep "\n" (p: "  - ${p}") problems}
    '';
    # Force the whole agent, not just the attributes read above.
    assert builtins.deepSeq agents true;
    helpers.mkMarker "check-herdr-launchd-regression" "herdr LaunchAgent runs the headless server with a pinned socket and a Nix-profile PATH.";

  # The failure this guards is silent in both directions: a declared hook whose
  # payload never renders leaves herdr on terminal heuristics, and a Claude
  # SessionStart entry that lands without the typed hooks nix-claude-code
  # renders would drop marketplace refresh from every session.
  herdr-integrations-regression =
    let
      files = hmConfig.config.home.file;
      claudeHooks = hmConfig.config.programs.claude.settings.hooks or { };
      sessionStart = claudeHooks.SessionStart or [ ];
      commands = lib.concatMap (entry: map (h: h.command or "") (entry.hooks or [ ])) sessionStart;
      declaresHerdr = lib.any (c: lib.hasInfix "herdr-agent-state.sh" c) commands;
      declaresTyped = lib.any (c: lib.hasInfix "session-start.sh" c) commands;

      expectedFiles = {
        claude = [ ".claude/hooks/herdr-agent-state.sh" ];
        codex = [
          ".codex/herdr-agent-state.sh"
          ".codex/hooks.json"
        ];
        opencode = [
          "${opencodeDir}/plugins/herdr-agent-state.js"
          "${opencodeDir}/herdr-tui-session.js"
          "${opencodeDir}/tui.jsonc"
        ];
      };

      missing = lib.concatMap (
        target: lib.filter (f: !(lib.hasAttr f files)) (expectedFiles.${target} or [ ])
      ) cfg.integrations;

      problems =
        lib.optional (missing != [ ])
          "declares integrations ${lib.concatStringsSep ", " cfg.integrations} but does not render: ${lib.concatStringsSep ", " missing}"
        ++ lib.optional (
          lib.elem "claude" cfg.integrations && !declaresHerdr
        ) "claude integration renders its hook but never registers it in settings.hooks.SessionStart"
        ++
          lib.optional (lib.elem "claude" cfg.integrations && claudeTypedSessionStart && !declaresTyped)
            "settings.hooks.SessionStart replaced the typed hook nix-claude-code renders instead of appending to it";
    in
    assert lib.assertMsg (problems == [ ]) ''
      herdr integrations are misdeclared:
      ${lib.concatMapStringsSep "\n" (p: "  - ${p}") problems}
    '';
    assert builtins.deepSeq (map (f: "${files.${f}.source}") (
      lib.concatMap (t: expectedFiles.${t} or [ ]) cfg.integrations
    )) true;
    helpers.mkMarker "check-herdr-integrations-regression" "herdr lifecycle hooks render and register for ${
      if cfg.integrations == [ ] then "no agents" else lib.concatStringsSep ", " cfg.integrations
    }.";

  herdr-agent-coverage-regression =
    assert
      uncovered == [ ]
      || throw ''
        herdr agent-detection coverage gap: ${lib.concatStringsSep ", " uncovered}

        These CLIs are enabled in this flake but herdr has no manifest for them,
        so their panes will show no working/blocked/idle state and nothing
        downstream (Slack alerts, `herdr agent wait`, dashboard approvals) will
        fire for them.

        Fix by adding an entry to programs.herdr.agentManifests. Author it
        against `herdr agent explain <target> --json` on a live pane — the rule
        schema is herdr's, so do not guess it. If the gap is deliberate for
        now, name it in programs.herdr.knownUnsupportedAgents instead, which
        makes it reviewable rather than invisible.
      '';
    helpers.mkMarker "check-herdr-agent-coverage-regression" "herdr detection covers all ${toString (lib.length enabledAgents)} enabled agent CLIs.";
}
