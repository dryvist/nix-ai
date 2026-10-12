# Router capability aliases — the ONE committed list every nix-ai consumer
# renders from (OpenCode's litellmRoles, Codex's per-alias profiles, ...).
#
# These are the chat capabilities nix-ai exposes to routed clients. Nix
# evaluation is pure and cannot fetch the router's live /v1/models at build
# time, so this list IS the git-declared model_group_alias contract;
# lib/checks/scripts/litellm-alias-subset-check.sh proves the router actually
# serves it (skips cleanly with no router credentials).
[
  "small"
  "medium"
  "large"
]
