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
  # Clean rolling aliases (no vendor prefix, no hardcoded versions).
  # Exposed in interactive coding tools (OpenCode) under the LiteLLM provider:
  #   litellm/deepseek-flash, litellm/qwen-max, litellm/glm-flash, litellm/minimax-m3
  cleanAliases = [
    "deepseek-flash"
    "qwen-max"
    "glm-flash"
    "minimax-m3"
  ];

  # Vendor-qualified IDs (matching OpenRouter / multi-provider convention)
  vendorModels = [
    "deepseek/deepseek-v4.1-flash"
    "qwen/qwen-max"
    "z-ai/glm-5.3-flash"
    "minimax/minimax-m3"
  ];

  # Canonical router models (clean rolling aliases)
  routerModels = [
    "deepseek-flash"
    "qwen-max"
    "glm-flash"
    "minimax-m3"
  ];

  # Models exposed in interactive coding tools (e.g. OpenCode).
  # Uses the clean aliases so they render without awkward nested vendor slashes.
  allExtraModels = [
    "deepseek-flash"
    "qwen-max"
    "glm-flash"
    "minimax-m3"
  ];
}
