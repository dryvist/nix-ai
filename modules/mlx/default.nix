{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.mlx;
  versions = import ../../lib/versions.nix;
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
      ;
  };
}
