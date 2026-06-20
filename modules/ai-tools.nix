# AI Development Tools
#
# Linters, formatters, and utilities specifically for AI coding workflows.
# These tools are NOT general-purpose development tools.
#
# ============================================================================
# PACKAGE HIERARCHY (STRICT - NO EXCEPTIONS)
# ============================================================================
#
# ALWAYS follow this order when choosing how to install a package:
#
# 1. **nixpkgs** (ALWAYS FIRST, NO EXCEPTIONS)
#    - Check: nix search nixpkgs <package>
#    - Use if package exists and is reasonably up-to-date
#    - Benefits: Binary cache, security updates, integration
#    - Example: github-mcp-server, terraform-mcp-server
#
# 2. **homebrew** (ONLY if not in nixpkgs)
#    - Fallback for packages missing from nixpkgs
#    - Check: brew search <package>
#    - Add to modules/darwin/homebrew.nix with clear justification
#    - Document WHY homebrew is needed (not in nixpkgs, severely outdated, etc.)
#
# 3. **bunx wrapper** (for npm packages not in nixpkgs or homebrew)
#    - Standard solution for npm/bun packages
#    - Always pin to specific version: package@x.y.z
#    - Downloads on first run, cached locally by bun
#    - Benefits: Simple, minimal code, easy version updates
#    - Pattern: writeShellScriptBin with bunx --bun
#
# 4. **uvx** (for Python packages not in nixpkgs or version-lagging)
#    - Standard solution for Python CLI tools
#    - Run on-demand: uvx <package>
#    - Benefits: Isolated environments, always-latest, no global pollution
#    - Replaced pipx (pipx removed from nix-home — antipattern in Nix env)
#
# ============================================================================
# CURRENT STATUS
# ============================================================================
#
# NIXPKGS PACKAGES (from nixpkgs, available on stable 25.11):
#   github-mcp-server, terraform-mcp-server, whisper-cpp, openai-whisper
#
# HOMEBREW PACKAGES (from modules/darwin/homebrew.nix):
#   codex: OpenAI Codex CLI (moved from nixpkgs to match claude/gemini pattern)
#   block-goose-cli: Block's AI agent (nixpkgs outdated at time of addition)
#   gemini-cli: Google Gemini CLI (moved from nixpkgs due to severe version lag)
#
# BUNX WRAPPER PACKAGES (npm packages not in nixpkgs/homebrew):
#   cclint: @felixgeelhaar/cclint (CLAUDE.md linter)
#   gh-copilot: @githubnext/github-copilot-cli (pinned version)
#   chatgpt: chatgpt-cli (ChatGPT terminal client)
#   claude-flow: claude-flow (multi-agent orchestration)
#   gws: @googleworkspace/cli (pinned version)
#
# UVX WRAPPER PACKAGES (Python packages not in nixpkgs/homebrew):
#   hf: huggingface-hub CLI (model downloads, used with HuggingFace MCP)
#   vllm-mlx: defined in modules/mlx.nix (owns the wrapper + LaunchAgent)
#
# DECLARATIVE MODULES (package + config managed by per-agent modules):
#   cecli      — actively maintained Aider fork; see modules/cecli/ (programs.cecli)
#   qwen-code  — Qwen agent CLI; see modules/qwen-code/ (programs.qwen-code)
#
# NOTE: These are home-manager packages, not system packages.
# Imported in hosts/macbook-m4/home.nix via home.packages.
#
# ============================================================================
# ADDING NEW NIXPKGS PACKAGES
# ============================================================================
#
# Packages are sourced from stable nixpkgs (25.11). To add a new one:
#   1. Verify availability: nix search nixpkgs <package>
#   2. Add to packages list below
#   3. Add to version check script (scripts/workflows/check-package-versions.sh)

{ pkgs, ... }:
let
  versions = import ../lib/versions.nix;
  cclintVersion = versions.cclint;
  ghCopilotVersion = versions.ghCopilot;
  chatgptCliVersion = versions.chatgptCli;
  claudeFlowVersion = versions.claudeFlow;
  gwsCliVersion = versions.gwsCli;
in
{
  # AI-specific development tools
  # Install via: home.packages = [ ... ] ++ (import ./ai-tools.nix { inherit pkgs; }).packages;
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
    # GitHub Copilot CLI
    # ==========================================================================
    # Source: https://github.com/github/gh-copilot
    # NPM: @githubnext/github-copilot-cli (pinned version)
    (writeShellScriptBin "gh-copilot" ''
      exec ${bun}/bin/bunx --bun @githubnext/github-copilot-cli@${ghCopilotVersion} "$@"
    '')

    # ==========================================================================
    # OpenAI ChatGPT CLI
    # ==========================================================================
    # Source: https://github.com/manno/chatgpt-cli
    # NPM: chatgpt-cli (pinned version)
    (writeShellScriptBin "chatgpt" ''
      exec ${bun}/bin/bunx --bun chatgpt-cli@${chatgptCliVersion} "$@"
    '')

    # ==========================================================================
    # Claude Flow - AI Agent Orchestration Platform
    # ==========================================================================
    # Source: https://github.com/ruvnet/claude-flow
    # NPM: claude-flow (pinned version)
    (writeShellScriptBin "claude-flow" ''
      exec ${bun}/bin/bunx --bun claude-flow@${claudeFlowVersion} "$@"
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
    # MCP Runtime Wrappers — moved to modules/mcp/module.nix (sub-flake)
    # ==========================================================================
    # The doppler-mcp and splunk-mcp-connect wrappers are now provided by the
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

    # ==========================================================================
    # AI agent CLIs (cecli, qwen-code)
    # ==========================================================================
    # Package install + configuration managed by per-agent modules:
    #   modules/cecli/      → programs.cecli      (uvx install)
    #   modules/qwen-code/  → programs.qwen-code  (homebrew install via nix-darwin)
    # See those modules for routing, model selection, and config generation.

  ];
}
