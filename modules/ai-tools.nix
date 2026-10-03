# AI Development Tools
#
# Linters, formatters, and utilities specifically for AI coding workflows.
# These tools are NOT general-purpose development tools.
#
# ============================================================================
# PACKAGE HIERARCHY (STRICT - NO EXCEPTIONS)
# ============================================================================
#
# nixpkgs -> llm-agents.nix -> homebrew (GUI + 2 CLIs) -> bunx wrapper -> uvx.
#
# The full decision matrix lives in modules/herdr/README.md. The short
# version: check `nix search nixpkgs <pkg>` first; reach for
# github:numtide/llm-agents.nix for an agent CLI nixpkgs does not carry;
# homebrew is GUI applications, plus exactly two CLI casks
# (claude-code@latest, codex) that must track upstream faster than a
# relock-and-rebuild cycle — darwin-only, config still in Nix, Linux
# unaffected. A cask cannot run on Linux guests, which used to pin this
# stack to one machine, so a third needs the same justification. bunx for
# npm packages, always version-pinned; uvx for Python CLI tools.
#
# ============================================================================
# CURRENT STATUS
# ============================================================================
#
# NIXPKGS: github-mcp-server, terraform-mcp-server, whisper-cpp,
#   openai-whisper, entire, yt-dlp, qwen-code, cursor-cli
#
# LLM-AGENTS.NIX: claude-code, antigravity-cli (`agy`), herdr, codex
#
# HOMEBREW (lib/homebrew.nix): block-goose-cli, langgraph-cli, the desktop
#   apps (claude, codex-app, chatgpt, antigravity, antigravity-ide), plus the
#   claude-code@latest and codex CLI casks (darwin only)
#
# ONE OWNER PER CLI. claude-code and codex come from Homebrew on darwin
#   (`package = null`; nix-ai still renders their config) and llm-agents.nix
#   on Linux. Never both. See modules/herdr/README.md.
#
# BUNX WRAPPER PACKAGES (npm packages not in nixpkgs/homebrew):
#   cclint: @felixgeelhaar/cclint (CLAUDE.md lint)
#   chatgpt: chatgpt-cli (ChatGPT terminal client)
#   gws: @googleworkspace/cli (pinned)
#   openwhispr: @openwhispr/cli (voice notes / transcription)
#   langfuse: langfuse-cli (Langfuse API CLI — traces, prompts, datasets)
#
# UVX WRAPPER PACKAGES (Python packages not in nixpkgs/homebrew):
#   hf: huggingface-hub CLI (model downloads, used with HuggingFace MCP)
#   mlx_lm.server: defined in modules/mlx (owns the wrapper + LaunchAgent)
#
# UNTRUSTED AGENT CLIs (gated by programs.ai.untrustedClis.enable, off by default):
#   copilot-cli, gh-copilot, claude-flow, omo-senpi — ./ai-tools/untrusted-clis.nix
#   cecli, qwen-code, opencode, cursor — per-agent modules under modules/
#
# NOTE: These are home-manager packages, not system packages.
# modules/default.nix imports this file unconditionally, for every host. It is
# not opt-in and not macOS-specific; per-platform differences belong in the
# package expressions below, never in whether this file is imported.
#
# ============================================================================
# ADDING NEW NIXPKGS PACKAGES
# ============================================================================
#
# Packages are sourced from stable nixpkgs (25.11). To add a new one:
#   1. Verify availability: nix search nixpkgs <package>
#   2. Add to packages list below

{ pkgs, ... }:
let
  versions = import ../lib/versions.nix;
  cclintVersion = versions.cclint;
  chatgptCliVersion = versions.chatgptCli;
  gwsCliVersion = versions.gwsCli;
  openwhisprCliVersion = versions.openwhisprCli;
  langfuseCliVersion = versions.langfuseCli;
in
{
  # AI-specific development tools
  # Consumed by modules/default.nix via `inherit (import ./ai-tools.nix ...) packages`.
  #
  # See CURRENT STATUS section at the top of this file for package details.
  packages = with pkgs; [
    # ==========================================================================
    # Speech-to-Text / Audio AI
    # ==========================================================================
    # Moved from nix-darwin environment.systemPackages — these are AI tools,
    # not system bootstrapping. sox/portaudio remain in nix-darwin (general C libs).

    whisper-cpp # Local speech-to-text (OpenAI Whisper C++ port, CoreML/Metal)
    openai-whisper # Original OpenAI Whisper (Python, GPU/CPU, broader model support)

    # ==========================================================================
    # Claude Code Ecosystem
    # ==========================================================================

    # CLAUDE.md linter - validates AI context files
    # Source: https://github.com/felixgeelhaar/cclint
    # NPM: @felixgeelhaar/cclint (pinned version)
    (writeShellScriptBin "cclint" ''
      exec ${bun}/bin/bunx --bun @felixgeelhaar/cclint@${cclintVersion} "$@"
    '')

    # ==========================================================================
    # MCP Servers (Model Context Protocol)
    # ==========================================================================
    # Used with Claude Code via `claude mcp add --scope user --transport stdio`
    # Configured in ~/.claude.json (user scope)

    # GitHub MCP Server - GitHub API integration
    # Source: https://github.com/github/github-mcp-server
    # Requires: GITHUB_PERSONAL_ACCESS_TOKEN env var
    github-mcp-server

    # Terraform MCP Server - Terraform/OpenTofu integration
    # Source: https://github.com/hashicorp/terraform-mcp-server
    terraform-mcp-server

    # ==========================================================================
    # yt-dlp — YouTube/multimedia content extraction
    # ==========================================================================
    # Used by fabric for YouTube transcript processing (`fabric -y URL --pattern X`).
    # Also generally useful for pipeline content extraction into fabric patterns
    # or the researcher agent workflow.
    # Source: https://github.com/yt-dlp/yt-dlp
    yt-dlp

    # ==========================================================================
    # entire — captures AI agent sessions alongside git commits
    # ==========================================================================
    # Records AI coding sessions and ties them to the commits they produced.
    # Source: https://github.com/entireio/cli
    entire

    # ==========================================================================
    # OpenAI ChatGPT CLI
    # ==========================================================================
    # Source: https://github.com/manno/chatgpt-cli
    # NPM: chatgpt-cli (pinned version)
    (writeShellScriptBin "chatgpt" ''
      exec ${bun}/bin/bunx --bun chatgpt-cli@${chatgptCliVersion} "$@"
    '')

    # ==========================================================================
    # Google Workspace CLI
    # ==========================================================================
    # Full Workspace API surface with curated Agent Skills (+triage, +watch, etc.)
    # Source: https://github.com/googleworkspace/cli
    # NPM: @googleworkspace/cli (pinned version)
    # Key commands: gws gmail +triage, gws gmail +watch, gws drive +upload
    (writeShellScriptBin "gws" ''
      exec ${bun}/bin/bunx --bun @googleworkspace/cli@${gwsCliVersion} "$@"
    '')

    # ==========================================================================
    # OpenWhispr CLI
    # ==========================================================================
    # Operates against the local desktop bridge or the cloud REST API.
    # Source: https://github.com/OpenWhispr/openwhispr-cli
    # NPM: @openwhispr/cli (pinned version)
    # Local mode: desktop app running (see nix-openwhispr). Remote mode:
    # `openwhispr auth login` stores key in ~/.openwhispr/cli-config.json.
    (writeShellScriptBin "openwhispr" ''
      exec ${bun}/bin/bunx --bun @openwhispr/cli@${openwhisprCliVersion} "$@"
    '')

    (import ./ai-tools/langfuse-cli.nix { inherit pkgs langfuseCliVersion; })
    (import ./ai-tools/rulesync.nix { inherit pkgs versions; })

    # ==========================================================================
    # MCP Runtime Wrappers — moved to modules/mcp/module.nix (sub-flake)
    # ==========================================================================
    # Any local MCP runtime wrapper a catalog entry needs is provided by the
    # MCP sub-flake's home-manager module (modules/mcp/module.nix). This keeps
    # all MCP runtime infrastructure self-contained inside the sub-flake so it
    # can be consumed cross-flake without a hidden dependency on this file.

    # ==========================================================================
    # HuggingFace Hub CLI
    # ==========================================================================
    # Download and manage models (especially MLX-quantized models).
    # Used alongside the HuggingFace MCP server: search via MCP, download via hf CLI.
    # Source: https://github.com/huggingface/huggingface_hub
    # PyPI: huggingface-hub (provides `hf` entry point)
    # Requires: HF_TOKEN env var (from macOS Keychain via nix-darwin shell init)
    (writeShellScriptBin "hf" ''
      exec ${uv}/bin/uvx --from "huggingface-hub==${versions.huggingfaceHub}" hf "$@"
    '')

  ];
}
