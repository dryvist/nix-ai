# Join shared runtime metadata with the local MLX serving catalog.
{
  catalogEntry,
  mlxCatalogEntry ? null,
  roleModel ? { },
}:
let
  sourceServing = (roleModel.serving or { }) // ((catalogEntry.stage0 or { }).serving or { });
  backend = if mlxCatalogEntry == null then null else mlxCatalogEntry.backend or "mlx-lm";
  serving =
    if backend == null then
      sourceServing
    else
      sourceServing
      // {
        inherit backend;
        endpoint = sourceServing.endpoint or "/v1/chat/completions";
      };
  mlxChat =
    backend != null
    && builtins.elem backend [
      "mlx-lm"
      "mlx-vlm"
    ]
    && (serving.endpoint or null) == "/v1/chat/completions";
in
{
  inherit serving mlxChat;
}
