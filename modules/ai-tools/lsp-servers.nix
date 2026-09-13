# Language servers for AI agent diagnostics.
#
# Consumed by the AI CLIs' LSP integrations: Claude Code "code intelligence"
# plugins, OpenCode's built-in servers, and OmO's LSP runtime on Codex. Each
# harness spawns the binary from PATH and injects post-edit diagnostics; none
# installs the binary itself. Only servers a session can hit in any repo live
# here — per-language servers belong in that repo's devShell (nix-devenv).
# NOTE: pyright's single owner is this list. nix-home's python-env.nix
# deliberately does not carry it (it needs no interpreter on PATH).
{ pkgs }:

with pkgs;
[
  nixd # Nix
  typescript-language-server # TS/JS
  bash-language-server # shell scripts
  pyright # Python
  terraform-ls # Terraform and OpenTofu (.tf and .tofu)
  yaml-language-server # YAML (playbooks, workflows, pipelines)
]
