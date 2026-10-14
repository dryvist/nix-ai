# The Qwen model mode is selected from the host's static resident contracts.
{ config, lib }:
let
  modelCatalog = import ../mlx/catalog-data.nix;
  routerCapabilities = (import ../litellm-local/aliases.nix) ++ [
    "embed"
    "ocr"
  ];
  residentContracts = config.programs.mlx.staticResidentContracts or { };
  qwenCatalogKeys = lib.filter (
    modelName:
    let
      entry = modelCatalog.${modelName};
    in
    lib.hasInfix "Qwen" entry.model
    && !(lib.elem modelName routerCapabilities)
    && !(lib.elem entry.model routerCapabilities)
  ) (lib.attrNames modelCatalog);
  residentQwenCatalogKeys = lib.filter (
    modelName: builtins.hasAttr (modelCatalog.${modelName}.model) residentContracts
  ) qwenCatalogKeys;
  defaultModel =
    if lib.elem "qwen38-27b" residentQwenCatalogKeys then
      "qwen38-27b"
    else
      builtins.head residentQwenCatalogKeys;
  modelId = modelName: (modelCatalog.${modelName} or { }).model or modelName;
  hasResidentModel = modelName: builtins.hasAttr (modelId modelName) residentContracts;
  endpoint =
    modelName:
    let
      model = modelId modelName;
      resident = residentContracts.${model} or null;
    in
    if resident == null then null else "http://127.0.0.1:${toString resident.servicePort}/v1";
in
{
  inherit
    residentContracts
    residentQwenCatalogKeys
    defaultModel
    modelId
    hasResidentModel
    endpoint
    ;
  bySize = residentQwenCatalogKeys != [ ];
  isQwenCatalogModel = modelName: lib.elem modelName qwenCatalogKeys;
}
