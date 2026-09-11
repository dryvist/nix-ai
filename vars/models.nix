# Central Model Catalog — Pure Data
#
# Committed root-level variable file defining external, cloud, and router models
# shared across agent modules and tooling (OpenCode, LiteLLM local, etc.).
#
# Note: Physical local MLX models are managed exclusively by modules/mlx/catalog-data*.nix
# and referenced via ai-stack capability roles to comply with the no-hardcoded-model-id lint gate.
#
# Edit this file to add, remove, or update models across all tooling.
{
  # Canonical non-MLX LiteLLM router models (cloud, flat-rate subscription models, rolling aliases)
  routerModels = [
    "deepseek/deepseek-v4.1-flash"
    "deepseek-flash"
    "qwen/qwen-max"
    "qwen-max"
    "qwen3.8-max"
    "z-ai/glm-5.3-flash"
    "minimax/minimax-m3"
  ];

  # Combined extra models to expose in interactive coding tools (e.g. OpenCode)
  allExtraModels = [
    "deepseek/deepseek-v4.1-flash"
    "deepseek-flash"
    "qwen/qwen-max"
    "qwen-max"
    "qwen3.8-max"
    "z-ai/glm-5.3-flash"
    "minimax/minimax-m3"
  ];
}
