# Central Model Catalog — Pure Data
#
# Committed root-level variable file defining external, cloud, and local models
# shared across agent modules and tooling (OpenCode, LiteLLM local, etc.).
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

  # MLX local community models
  mlxModels = [
    "mlx-community/Qwen3.8-27B-4bit"
    "mlx-community/Qwen3.6-35B-A3B-4bit"
    "mlx-community/Qwen3.5-9B-MLX-4bit"
  ];

  # Combined models exposed in interactive coding tools (e.g. OpenCode)
  allExtraModels = [
    "deepseek/deepseek-v4.1-flash"
    "deepseek-flash"
    "qwen/qwen-max"
    "qwen-max"
    "qwen3.8-max"
    "z-ai/glm-5.3-flash"
    "minimax/minimax-m3"
    "mlx-community/Qwen3.8-27B-4bit"
    "mlx-community/Qwen3.6-35B-A3B-4bit"
    "mlx-community/Qwen3.5-9B-MLX-4bit"
  ];
}
