# programs.agentHooks.codexQuotaPush: the script behaviour runs from
# tests/test-codex-quota-push.sh; the checks here pin the module's Nix surface,
# which is the launchd schedule and environment, the assertions and the
# default-off state.
{
  pkgs,
  src,
  hmConfig,
  mkHmConfig,
  mkHmConfigDarwin,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs.lib) hasInfix hasSuffix;
  url = "http://push.example.test/api/v1/import/prometheus";
  tokenFile = "/var/run/codex-quota-token";
  pushOn = {
    programs.agentHooks.codexQuotaPush = {
      enable = true;
      inherit url tokenFile;
    };
  };
  intervalOne = {
    programs.agentHooks.codexQuotaPush = {
      enable = true;
      inherit url tokenFile;
      intervalMinutes = 1;
    };
  };
  agent = (mkHmConfigDarwin [ pushOn ]).config.launchd.agents.codex-quota-push.config;
  minutes = map (e: e.Minute) agent.StartCalendarInterval;
  agentArgs = agent.ProgramArguments;
  agentEnv = agent.EnvironmentVariables;
  pushAsserts = cfg: builtins.filter (a: hasInfix "codexQuotaPush" a.message) cfg.config.assertions;
  allPass = cfg: builtins.all (a: a.assertion) (pushAsserts cfg);
  # Home Manager throws "Failed assertions" once a failing entry is forced. A
  # throw makes tryEval report value = false, so a rejected config reads as false.
  rejects = cfg: !(builtins.tryEval (allPass cfg)).value;
in
{
  codex-quota-push-script = pkgs.runCommand "check-codex-quota-push-script" {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.jq
    ];
  } "bash ${src}/tests/test-codex-quota-push.sh && touch $out";

  codex-quota-push-launchd =
    assert agent.RunAtLoad == false || throw "codex-quota-push must not run at load";
    assert
      minutes == [
        3
        8
        13
        18
        23
        28
        33
        38
        43
        48
        53
        58
      ]
      || throw "codex-quota-push must run at minutes 3, 8, ... 58 for a five-minute interval";
    assert
      builtins.length agentArgs == 2
      && hasSuffix "/bin/agent-quota-push" (builtins.head agentArgs)
      && hasSuffix "/bin/codex-quota-metrics" (builtins.elemAt agentArgs 1)
      || throw "codex-quota-push must run agent-quota-push with the Codex reader as its one reader";
    assert
      agentEnv.AGENT_QUOTA_WRITE_URL == url && agentEnv.AGENT_QUOTA_WRITE_TOKEN_FILE == tokenFile
      || throw "codex-quota-push must pass the URL and token file path through AGENT_QUOTA_WRITE_URL and AGENT_QUOTA_WRITE_TOKEN_FILE";
    helpers.mkMarker "check-codex-quota-push-launchd" "codex-quota-push: launchd schedule, reader list and environment as declared";

  codex-quota-push-assertions =
    assert
      allPass (mkHmConfigDarwin [ pushOn ])
      || throw "a complete codexQuotaPush config must pass its assertions";
    assert
      !(rejects (mkHmConfigDarwin [ pushOn ]))
      || throw "rejects must read false for a valid config, or the negative checks below are vacuous";
    assert
      rejects (mkHmConfig [ { programs.agentHooks.codexQuotaPush.enable = true; } ])
      || throw "codexQuotaPush.enable without url and tokenFile must fail an assertion";
    assert
      rejects (mkHmConfigDarwin [ intervalOne ])
      || throw "a codexQuotaPush interval that puts a run on :15 must fail an assertion";
    helpers.mkMarker "check-codex-quota-push-assertions" "codex-quota-push: url, tokenFile and schedule assertions enforced";

  codex-quota-push-default-off =
    assert
      !(hmConfig.config.launchd.agents ? codex-quota-push)
      || throw "codex-quota-push agent must not exist when codexQuotaPush is disabled (default)";
    assert
      !hmConfig.config.programs.agentHooks.codexQuotaPush.enable
      || throw "codexQuotaPush must default to disabled";
    helpers.mkMarker "check-codex-quota-push-default-off" "codex-quota-push: off by default";
}
