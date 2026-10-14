# Qwen Code must use the shared deny-default Seatbelt boundary without inheriting
# OpenCode's app grants or credentials from the caller's environment.
{
  pkgs,
  hmConfig,
  hmConfigLitellmLocal,
  hmConfigQwenRouter,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };

  profile = builtins.readFile ../../modules/opencode/opencode.sb;
  launcher = builtins.readFile ../../modules/opencode/scripts/launch.sh;
  renderer = builtins.readFile ../../modules/opencode/sandbox.nix;
  qwenSandbox = builtins.readFile ../../modules/qwen-code/sandbox.nix;
  qwenModule = builtins.readFile ../../modules/qwen-code/default.nix;
  qwenOptions = builtins.readFile ../../modules/qwen-code/options.nix;
  qwenSettings = builtins.readFile ../../modules/qwen-code/settings.nix;
  cfg = hmConfig.config.programs.qwen-code;
  routerCfg = hmConfigQwenRouter.config.programs.qwen-code;
  localProxyCfg = hmConfigLitellmLocal.config.programs.qwen-code;
  homeDir = hmConfig.config.home.homeDirectory;
  installedQwen = builtins.filter (
    package: (package.pname or "") == "qwen-code"
  ) hmConfig.config.home.packages;

  requiredProfile = [
    "(deny default)"
    "(deny network-outbound (remote unix-socket))"
    ''(deny network-outbound (remote ip "localhost:*"))''
    "@APP_READ_RULES@"
    "@APP_STATE_RULES@"
  ];
  missingProfile = builtins.filter (needle: !(lib.hasInfix needle profile)) requiredProfile;
  requiredQwenSandbox = [
    "literal"
    "readRules = ["
    ".qwen/settings.json"
    "subpath"
    ".qwen/skills"
    "statePaths = ["
    ".qwen/history"
    ".qwen/file-history"
    ".qwen/tmp"
    "projectConfigFileRegex"
    "projectConfigDirRegex"
    ".qwen/output-language.md"
    "appWriteExceptionRule = ''"
    "OPENAI_API_KEY"
    "OPENAI_BASE_URL"
  ];
  missingQwenSandbox = builtins.filter (
    needle: !(lib.hasInfix needle qwenSandbox)
  ) requiredQwenSandbox;
  forbiddenEnv = [
    "DOPPLER_"
    "VAULT_"
    "BAO_"
    "OPENBAO_"
    "GH_TOKEN"
    "GITHUB_TOKEN"
    "AWS_"
    "SSH_AUTH_SOCK"
  ];
  leakedEnv = builtins.filter (
    name: lib.hasInfix name qwenSandbox || lib.hasInfix name launcher
  ) forbiddenEnv;
  wiringIntact =
    lib.hasInfix "import ./endpoint.nix { inherit config; }" qwenModule
    && lib.hasInfix "import ./endpoint.nix { inherit config; }" qwenSettings
    && lib.hasInfix "modelMode.endpoint modelName" qwenModule
    && lib.hasInfix "modelMode.endpoint modelName" qwenSettings
    && lib.hasInfix "sandboxLocalPorts = localPorts;" qwenModule
    && lib.hasInfix "lib.optional (loopbackEndpoint != null)" qwenModule
    && lib.hasInfix "if cfg.sandbox.enable then sandboxedQwen else cfg.package" qwenModule
    && lib.hasInfix "pkgs.stdenv.hostPlatform.isDarwin" qwenOptions
    && lib.hasInfix "cfg.package != null" qwenModule
    && lib.hasInfix "if litellmLocal.enable then" qwenSettings
    && lib.hasInfix ''"QWEN_LOCAL_DUMMY_KEY"'' qwenSettings
    && lib.hasInfix ''"OPENAI_API_KEY"'' qwenSettings;
  qwenDoesNotGetOtherTools =
    !(lib.hasInfix ".config/opencode" qwenSandbox)
    && !(lib.hasInfix ".local/share/opencode" qwenSandbox)
    && !(lib.hasInfix ".claude" qwenSandbox)
    && !(lib.hasInfix ".codex" qwenSandbox);
  openCodeDefaultsIntact =
    lib.hasInfix ''projectConfigFileRegex ? "opencode\\.json"'' renderer
    && lib.hasInfix ''projectConfigDirRegex ? "\\.opencode"'' renderer
    && lib.hasInfix ".config/opencode" renderer
    && lib.hasInfix ".local/share/opencode" renderer;
in
{
  qwen-code-sandbox-regression =
    assert lib.assertMsg (
      missingProfile == [ ]
    ) "shared Seatbelt profile lost rules: ${lib.concatStringsSep ", " missingProfile}";
    assert lib.assertMsg (missingQwenSandbox == [ ])
      "Qwen sandbox lost required grants or router variables: ${lib.concatStringsSep ", " missingQwenSandbox}";
    assert lib.assertMsg (
      leakedEnv == [ ]
    ) "Qwen sandbox names forbidden environment variables: ${lib.concatStringsSep ", " leakedEnv}";
    assert lib.assertMsg wiringIntact "Qwen sandbox module wiring changed";
    assert lib.assertMsg qwenDoesNotGetOtherTools
      "Qwen sandbox gained another agent's config directory";
    assert lib.assertMsg openCodeDefaultsIntact
      "the shared renderer changed OpenCode's app-specific grants";
    assert cfg.sandbox.enable == pkgs.stdenv.hostPlatform.isDarwin;
    assert cfg.sandbox.workRoot == "${homeDir}/qwen-code-work";
    assert cfg.package != null;
    assert !cfg.sandbox.enable || builtins.any (package: package ? sandboxProfile) installedQwen;
    assert cfg.sandboxLocalPorts == [ 11427 ];
    assert routerCfg.sandboxLocalPorts == [ ];
    assert
      localProxyCfg.sandboxLocalPorts == [ hmConfigLitellmLocal.config.programs.litellmLocal.port ];
    helpers.mkMarker "check-qwen-code-sandbox-regression" "Qwen Code sandbox ports follow each host's selected endpoint";
}
