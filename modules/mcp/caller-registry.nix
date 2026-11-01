{
  config,
  lib,
  ...
}:
let
  homelabContracts = config._module.args."homelab-contracts" or null;
  callerRegistry =
    if homelabContracts == null then
      null
    else
      let
        callerPolicy = builtins.fromJSON (
          builtins.readFile "${homelabContracts}/ansible/roles/agent_callers/files/callers.json"
        );
      in
      if callerPolicy.schema_version == 1 then
        callerPolicy
      else
        throw "homelab-contracts agent callers must use schema_version 1";
in
{
  options.programs.aiMcp = {
    callerRegistry = lib.mkOption {
      type = lib.types.nullOr (lib.types.attrsOf lib.types.unspecified);
      readOnly = true;
      internal = true;
      default = callerRegistry;
      description = "Caller registry loaded from homelab-contracts for validated gateway-key derivation.";
    };

    gatewayKeyLaunchPrefixFor = lib.mkOption {
      type = lib.types.nullOr (lib.types.functionTo (lib.types.listOf lib.types.str));
      default = null;
      description = ''
        Maps a registered harness caller ID and its derived gateway-key
        environment-variable name to the argv prefix that supplies the key.
        The prefix is used only when that key is not already set; it receives
        `{ callerId, env }` and remains responsible for its own failure behavior.
      '';
    };
  };
}
