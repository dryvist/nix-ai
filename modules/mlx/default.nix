{
  config,
  lib,
  pkgs,
  nixAiRev,
  ...
}:
let
  cfg = config.programs.mlx;
  versions = import ../../lib/versions.nix;
  clusterSoftwareJson = builtins.toJSON {
    nix_ai = nixAiRev;
    inherit (versions) mlx;
    mlx_lm = versions.mlxLm;
    macos = "";
    model = cfg.clusterMode.model;
    model_revision = "";
  };
  parakeetMlxVersion = versions.parakeetMlx;
  inherit (versions) mlxVlmInstallSpec;
  uvPythonVersion = (import ../../lib/python.nix { inherit pkgs; }).pythonVersion;

  mlxLmServer = import ./mlx-lm-server.nix {
    inherit pkgs cfg versions;
  };
  mlxVlmServer = import ./mlx-vlm-server.nix {
    inherit pkgs mlxVlmInstallSpec uvPythonVersion;
  };
  mlxModelServerPkgs = {
    mlx-lm = mlxLmServer.pkg;
    mlx-vlm = mlxVlmServer.pkg;
    mlx-vlm-native = mlxVlmServer.nativePkg;
  };
  mlxModelServerPkg = mlxModelServerPkgs.${cfg.modelServerBackend};
  apiUrl = "http://${cfg.host}:${toString cfg.port}/v1";

  # The cluster lifecycle module uses these identifiers when it quiesces
  # standalone serving. Labels are taken from the selected resident contracts.
  residentAgentLabels = map (contract: contract.launchdLabel) (
    lib.attrValues cfg.staticResidentContracts
  );
  inherit (import ./serving-label.nix { inherit lib; }) isServingLabel;
  servingAgentLabels = map (agent: agent.config.Label) (
    lib.attrValues (
      lib.filterAttrs (_: agent: agent.enable && isServingLabel agent.config.Label) config.launchd.agents
    )
  );
  watchdogAgentLabel = "dev.mlx-model-server.watchdog";

  inherit
    (import ./model-server-pattern.nix {
      inherit
        lib
        cfg
        mlxLmServer
        mlxVlmServer
        ;
    })
    modelServerProcessPattern
    ;
  inherit (import ./worker-env.nix { inherit lib cfg; }) workerEnv;
  inherit
    (import ./model-server-cmd.nix {
      inherit
        lib
        cfg
        mlxModelServerPkg
        mlxModelServerPkgs
        ;
    })
    mkModelArgs
    ;
in
{
  imports = import ./imports.nix;

  # A serving agent whose launchd override is disabled stays down across converges,
  # so every declared serving label is enabled before the agents are set up.
  home.activation.enableMlxServingAgents = lib.mkIf (cfg.enable && servingAgentLabels != [ ]) (
    lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ] ''
      uid="$(id -u)"
      ${lib.concatMapStringsSep "\n" (label: ''
        run /bin/launchctl enable "gui/$uid/${label}"
      '') servingAgentLabels}
    ''
  );

  _module.args.mlxShared = {
    inherit
      cfg
      mlxModelServerPkg
      mlxModelServerPkgs
      mkModelArgs
      workerEnv
      parakeetMlxVersion
      mlxVlmInstallSpec
      apiUrl
      uvPythonVersion
      residentAgentLabels
      watchdogAgentLabel
      modelServerProcessPattern
      clusterSoftwareJson
      ;
  };
}
