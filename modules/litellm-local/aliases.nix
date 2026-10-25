# Default router capability aliases come from
# homelab-contracts/ansible/roles/llm_roles/files/lanes.json; deployments may
# override programs.litellmLocal.aliases.
#
{ src }:
(import ../../lib/lanes.nix { inherit src; }).harness_aliases
