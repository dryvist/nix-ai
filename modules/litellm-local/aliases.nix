# Router capability aliases — the ONE committed list every nix-ai consumer
# renders from (OpenCode's litellmRoles, Codex's per-alias profiles, ...).
#
# These are the chat capabilities nix-ai exposes to routed clients. Nix
# evaluation is pure and cannot fetch the router's live /v1/models at build
# time, so this list IS the git-declared model_group_alias contract;
# modules/scripts/litellm-alias-subset-check.sh proves the router actually
# serves it (skips cleanly with no router credentials).
#
# Lanes plus the legacy synonyms kept for one release (small, medium). `large`
# is retired in favour of `critical`. Every name here must be in `laneVocabulary`
# (lib/checks/litellm-local-aliases.nix), identical to ansible-proxmox-ai
# LANE_VOCABULARY.
[
  "auto"
  "light"
  "standard"
  "critical"
  "long"
  "small"
  "medium"
]
