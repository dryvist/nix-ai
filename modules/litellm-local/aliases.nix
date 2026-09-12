# Router capability aliases — the ONE committed list every nix-ai consumer
# renders from (OpenCode's litellmRoles, Codex's per-alias profiles, ...).
#
# Nix evaluation is pure and cannot fetch the router's live /v1/models at
# build time, so this list IS the git-declared model_group_alias contract
# (operator decision, Vikunja 3076/W1 A2) — the same split fallback-tier.nix
# already uses between declared names and upstream resolution: this file
# names the contract, lib/checks/scripts/litellm-alias-subset-check.sh proves
# the router actually serves it (skips cleanly with no router credentials,
# since that check needs network access a pure eval cannot have).
#
# Legacy names (lead, subagent, ocr) are NOT here. The router keeps them as
# synonyms for one release, then retires them — nothing in this repo should
# reference them going forward.
[
  "best"
  "default"
  "fast"
  "cheap"
  "embed"
  "judge"
  "long"
]
