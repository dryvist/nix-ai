# Qwen Code module regression tests
{
  pkgs,
  hmConfig,
  hmConfigLitellmLocal,
  hmConfigQwenRouter,
  hmConfigQwenMissingResident,
  hmConfigStaticServing,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  routerAliases = hmConfig.config.programs.litellmLocal.aliases;
  routerCapabilities = routerAliases ++ [
    "embed"
    "ocr"
  ];
  cfg = hmConfig.config.programs.qwen-code;
  homeDir = hmConfig.config.home.homeDirectory;
  untrustedMode = import ../../modules/qwen-code/model-mode.nix {
    inherit (hmConfig) config;
    inherit lib;
  };
  staticCfg = hmConfigStaticServing.config.programs.qwen-code;
  staticSettings = staticCfg.generatedSettings;
  staticMode = import ../../modules/qwen-code/model-mode.nix {
    inherit (hmConfigStaticServing) config;
    inherit lib;
  };
  modelId = staticMode.modelId staticCfg.model;
  residentModels = staticMode.residentContracts;
  staticEndpoint = staticMode.endpoint staticCfg.model;
  routerCfg = hmConfigQwenRouter.config.programs.qwen-code;
  routerSettings = routerCfg.generatedSettings;
  qwenModuleSource = builtins.readFile ../../modules/qwen-code/default.nix;
  missingResidentEvaluation = builtins.tryEval (
    builtins.deepSeq hmConfigQwenMissingResident.config.assertions true
  );
  missingResidentMessage = "programs.qwen-code.model names a Qwen catalog key without a static MLX resident on this host.";
  routerMode = import ../../modules/qwen-code/model-mode.nix {
    inherit (hmConfigQwenRouter) config;
    inherit lib;
  };
  localProxySettings = hmConfigLitellmLocal.config.programs.qwen-code.generatedSettings;
  routerProviderEntries =
    endpoint:
    map (name: {
      id = name;
      inherit name;
      baseUrl = endpoint;
      envKey = "OPENAI_API_KEY";
      description = "${name} router capability";
    }) routerAliases;
in
{
  # Verify all expected Qwen Code option paths exist.
  qwen-code-options-regression = helpers.mkOptionsRegression {
    label = "Qwen Code";
    checkName = "check-qwen-code-options-regression";
    inherit cfg;
    expectedOptions = [
      "contextFileNames"
      "enable"
      "excludedMcpServers"
      "extraSettings"
      "generatedSettings"
      "installVia"
      "mcpServerNames"
      "model"
      "models"
      "sandbox"
      "sandboxLocalPorts"
    ];
  };

  # Untrusted CLI hosts without a static Qwen resident keep their old local defaults.
  qwen-code-defaults-regression = helpers.mkDefaultsRegression {
    label = "Qwen Code";
    checkName = "check-qwen-code-defaults-regression";
    checks = [
      {
        name = "qwen-code.enable";
        actual = cfg.enable;
        expected = true;
      }
      {
        name = "qwen-code.model";
        actual = cfg.model;
        expected = "coding";
      }
      {
        name = "untrusted fixture selects the legacy mode";
        actual = untrustedMode.bySize;
        expected = false;
      }
      {
        name = "untrusted fixture has no by-size model list";
        actual = cfg.models;
        expected = [ ];
      }
      {
        name = "qwen-code.contextFileNames";
        actual = cfg.contextFileNames;
        expected = [ "AGENTS.md" ];
      }
      {
        name = "qwen-code.sandbox.enable";
        actual = cfg.sandbox.enable;
        expected = pkgs.stdenv.hostPlatform.isDarwin;
      }
      {
        name = "qwen-code.sandbox.workRoot";
        actual = cfg.sandbox.workRoot;
        expected = "${homeDir}/qwen-code-work";
      }
    ];
  };

  # Router-only and local-proxy hosts keep the pre-existing capability default.
  qwen-code-routed-defaults-regression = helpers.mkDefaultsRegression {
    label = "Qwen Code routed model defaults";
    checkName = "check-qwen-code-routed-defaults-regression";
    checks = [
      {
        name = "qwen-code.model.local-proxy";
        actual = hmConfigLitellmLocal.config.programs.qwen-code.model;
        expected = "medium";
      }
      {
        name = "qwen-code.model.router";
        actual = routerCfg.model;
        expected = "medium";
      }
    ];
  };

  qwen-code-model-defaults-regression = helpers.mkDefaultsRegression {
    label = "Qwen Code model defaults";
    checkName = "check-qwen-code-model-defaults-regression";
    checks = [
      {
        name = "qwen-code.model.static-resident";
        actual = staticCfg.model;
        expected = "qwen35-9b";
      }
      {
        name = "qwen-code.models.static-resident";
        actual = staticCfg.models;
        expected = [
          "qwen35-9b"
          "qwen38-27b"
        ];
      }
      {
        name = "qwen-code.models.router-only";
        actual = routerCfg.models;
        expected = [ ];
      }
    ];
  };

  # These are the old settings.nix values: router aliases, endpoint, env key and
  # default model are compared after the actual Qwen settings renderer expands them.
  qwen-code-router-settings-regression = helpers.mkDefaultsRegression {
    label = "Qwen Code router-only rendered settings";
    checkName = "check-qwen-code-router-settings-regression";
    checks = [
      {
        name = "router fixture has no static Qwen resident";
        actual = routerMode.residentQwenCatalogKeys;
        expected = [ ];
      }
      {
        name = "router fixture enables Qwen Code";
        actual = routerCfg.enable;
        expected = true;
      }
      {
        name = "router fixture assertions pass with Qwen enabled";
        actual = builtins.all (assertion: assertion.assertion) hmConfigQwenRouter.config.assertions;
        expected = true;
      }
      {
        name = "router default model";
        actual = routerSettings.model.name;
        expected = "medium";
      }
      {
        name = "router provider entries match capability aliases";
        actual = routerSettings.modelProviders.openai;
        expected = routerProviderEntries "https://router.example.invalid/v1";
      }
      {
        name = "router provider environment";
        actual = routerSettings.env;
        expected = { };
      }
      {
        name = "router sandbox loopback ports";
        actual = routerCfg.sandboxLocalPorts;
        expected = [ ];
      }
      {
        name = "local-proxy default model";
        actual = localProxySettings.model.name;
        expected = "medium";
      }
      {
        name = "local-proxy provider entries match capability aliases";
        actual = localProxySettings.modelProviders.openai;
        expected = routerProviderEntries hmConfigLitellmLocal.config.programs.litellmLocal.baseUrl;
      }
      {
        name = "local-proxy provider environment";
        actual = localProxySettings.env;
        expected = { };
      }
      {
        name = "local-proxy sandbox loopback ports";
        actual = hmConfigLitellmLocal.config.programs.qwen-code.sandboxLocalPorts;
        expected = [ hmConfigLitellmLocal.config.programs.litellmLocal.port ];
      }
    ];
  };

  qwen-code-missing-resident-regression = helpers.mkDefaultsRegression {
    label = "Qwen Code missing resident assertion";
    checkName = "check-qwen-code-missing-resident-regression";
    checks = [
      {
        name = "explicit Qwen catalog key without resident is rejected";
        actual = !missingResidentEvaluation.success;
        expected = true;
      }
      {
        name = "rejection reports the Qwen model option";
        actual = lib.hasInfix missingResidentMessage qwenModuleSource;
        expected = true;
      }
    ];
  };

  qwen-code-model-contract-regression = helpers.mkDefaultsRegression {
    label = "Qwen Code local catalog model";
    checkName = "check-qwen-code-model-contract-regression";
    checks = [
      {
        name = "host with a static Qwen resident selects by-size mode";
        actual = staticMode.bySize;
        expected = true;
      }
      {
        name = "static-resident fixture enables Qwen and passes assertions";
        actual =
          staticCfg.enable
          && builtins.all (assertion: assertion.assertion) hmConfigStaticServing.config.assertions;
        expected = true;
      }
      {
        name = "selected model is in the allowed set";
        actual = builtins.elem staticCfg.model staticCfg.models;
        expected = true;
      }
      {
        name = "selected model is a Qwen catalog key";
        actual = staticMode.isQwenCatalogModel staticCfg.model;
        expected = true;
      }
      {
        name = "allowed models are Qwen catalog keys rather than aliases";
        actual = lib.all (
          modelName:
          staticMode.isQwenCatalogModel modelName
          && !(builtins.elem modelName routerCapabilities)
          && !(builtins.elem (staticMode.modelId modelName) routerCapabilities)
        ) staticCfg.models;
        expected = true;
      }
      {
        name = "selected model and physical id are not router capabilities";
        actual =
          !(builtins.elem staticCfg.model routerCapabilities) && !(builtins.elem modelId routerCapabilities);
        expected = true;
      }
      {
        name = "selected physical model id";
        actual = modelId;
        expected = "mlx-community/Qwen3.5-9B-OptiQ-4bit";
      }
      {
        name = "selected model is statically resident";
        actual = builtins.hasAttr modelId residentModels;
        expected = true;
      }
      {
        name = "endpoint is the resident model server";
        actual = staticEndpoint;
        expected = "http://127.0.0.1:11409/v1";
      }
      {
        name = "the larger resident stays selectable on its own endpoint";
        actual = [
          (staticMode.modelId "qwen38-27b")
          (staticMode.endpoint "qwen38-27b")
        ];
        expected = [
          "mlx-community/Qwen3.8-27B-4bit"
          "http://127.0.0.1:11427/v1"
        ];
      }
      {
        name = "rendered default names the physical model";
        actual = staticSettings.model.name;
        expected = modelId;
      }
      {
        name = "rendered provider model names the physical model";
        actual = map (entry: entry.name) staticSettings.modelProviders.openai;
        expected = [
          modelId
          (staticMode.modelId "qwen38-27b")
        ];
      }
      {
        name = "rendered provider points at the resident endpoint";
        actual = map (entry: entry.baseUrl) staticSettings.modelProviders.openai;
        expected = [
          staticEndpoint
          (staticMode.endpoint "qwen38-27b")
        ];
      }
      {
        name = "rendered provider uses the local dummy key";
        actual = map (entry: entry.envKey) staticSettings.modelProviders.openai;
        expected = [
          "QWEN_LOCAL_DUMMY_KEY"
          "QWEN_LOCAL_DUMMY_KEY"
        ];
      }
    ];
  };
}
