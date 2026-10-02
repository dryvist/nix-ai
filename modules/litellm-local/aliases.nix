# Router capability aliases — the ONE committed list every nix-ai consumer
# renders from (OpenCode's litellmRoles, Codex's per-alias profiles, ...).
#
# Derived from the role map (lib/role-map.nix): every role it names is an
# alias. Nix evaluation is pure and cannot fetch the router's live /v1/models
# at build time, so this list IS the git-declared model_group_alias contract;
# lib/checks/scripts/litellm-alias-subset-check.sh proves the router actually
# serves it (skips cleanly with no router credentials).
#
# Retired names (lead, subagent, quickest, tool-calling, large-context,
# most-capable, oss, goal-judge, interim-brain) are not here; the router keeps
# them as synonyms for one release, then retires them.
builtins.attrNames (import ../../lib/role-map.nix { }).roles
