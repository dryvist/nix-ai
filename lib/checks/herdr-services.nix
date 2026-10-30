{ pkgs, hmConfigDarwin }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
in
{
  # The TUI is a client, so a module that installs the binary and renders
  # config.toml without declaring a service yields no running herd at all —
  # invisible in the rendered config and raising no error anywhere.
  herdr-launchd-regression =
    let
      agents = hmConfigDarwin.config.launchd.agents;
      absent = throw "herdr: no launchd agent is declared, so the server never runs and the herd stays empty; see nix-herdr user server module";
      agent = (agents.herdr or absent).config;
      args = agent.ProgramArguments;
      env = agent.EnvironmentVariables or { };
      expectedSocket = "${hmConfigDarwin.config.xdg.configHome}/herdr/herdr.sock";
      profileBin = "/etc/profiles/per-user/${hmConfigDarwin.config.home.username}/bin";
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

  herdr-hail-darwin-eval =
    let
      cfg = hmConfigDarwin.config;
      hail = cfg.services.herdr.hail;
      agent = cfg.launchd.agents.herdr-hail.config;
      env = agent.EnvironmentVariables;
      prefix = [
        "runtime-secret-launcher"
        "run"
        "--"
      ];
    in
    assert hail.launchPrefix == prefix;
    assert agent.ProgramArguments == prefix ++ [ (lib.getExe hail.package) ];
    assert agent.KeepAlive && agent.RunAtLoad;
    assert env.HERDR_SOCKET_PATH == "${cfg.xdg.configHome}/herdr/herdr.sock";
    assert lib.hasSuffix "/herdr-hail-config" env.HERDR_PLUGIN_CONFIG_DIR;
    assert hail.settings.slack.enabled;
    assert lib.all (name: !(lib.hasAttr name env)) [
      "SLACK_BOT_TOKEN"
      "SLACK_APP_TOKEN"
      "DISCORD_BOT_TOKEN"
    ];
    helpers.mkMarker "check-herdr-hail-darwin-eval" "herdr Hail Darwin LaunchAgent and runtime argument prefix evaluated.";
}
