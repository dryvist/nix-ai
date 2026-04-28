# Shared MCP Servers Catalog
#
# Portable MCP server definitions using standard commands.
# Uses bunx for npm packages and uvx for Python packages.
#
# Official MCP Servers: https://github.com/modelcontextprotocol/servers
#
# Servers requiring API keys read them from environment variables. Use your
# secrets manager (Doppler, Keychain, etc.) to inject env vars.

let
  # bunx helper - command only, args set inline per server so Renovate's
  # regex manager can match literal "@scope/pkg@version" strings in the source.
  bunx = args: {
    command = "bunx";
    inherit args;
  };
in
{
  # ================================================================
  # Official Anthropic MCP Servers
  # ================================================================
  # Versions pinned as literal strings for Renovate regex tracking.
  # Archived servers remain unpinned unless a maintained replacement exists.

  everything = bunx [ "@modelcontextprotocol/server-everything@2026.1.26" ];
  fetch = bunx [ "@modelcontextprotocol/server-fetch" ]; # archived
  filesystem = bunx [ "@modelcontextprotocol/server-filesystem@2026.1.14" ];
  git = bunx [ "@modelcontextprotocol/server-git" ]; # archived
  memory = bunx [ "@modelcontextprotocol/server-memory@2026.1.26" ];
  sequentialthinking = bunx [ "@modelcontextprotocol/server-sequential-thinking" ]; # archived
  time = {
    command = "uvx";
    args = [
      "--from"
      "mcp-server-time==2026.1.26"
      "mcp-server-time"
    ];
  };
  docker = bunx [ "@modelcontextprotocol/server-docker" ]; # archived
  exa = bunx [ "@modelcontextprotocol/server-exa" ] // {
    disabled = true;
  }; # archived; Requires: EXA_API_KEY
  firecrawl = bunx [ "@modelcontextprotocol/server-firecrawl" ] // {
    disabled = true;
  }; # archived; Requires: FIRECRAWL_API_KEY
  cloudflare = bunx [ "@modelcontextprotocol/server-cloudflare" ] // {
    disabled = true;
  }; # archived; Requires: CLOUDFLARE_API_TOKEN
  aws = bunx [ "@modelcontextprotocol/server-aws-kb-retrieval@0.6.2" ]; # Requires: AWS credentials

  # ================================================================
  # Native nixpkgs packages
  # ================================================================

  # Terraform - terraform-mcp-server from nixpkgs.
  terraform = {
    command = "terraform-mcp-server";
  };

  # GitHub - github-mcp-server from nixpkgs.
  # Requires: GITHUB_PERSONAL_ACCESS_TOKEN env var (not yet in Doppler).
  github = {
    command = "github-mcp-server";
    disabled = true;
  };

  # ================================================================
  # Third-party npm packages
  # ================================================================

  # Context7 - provided by context7@claude-plugins-official plugin.
  # Do NOT define here - the plugin manages its own MCP server lifecycle.

  # ================================================================
  # PAL MCP - Multi-model orchestration
  # ================================================================
  # Transport: stdio, launched via pal-mcp wrapper (modules/claude/pal-models.nix).
  pal = {
    command = "pal-mcp";
  };

  # ================================================================
  # HuggingFace MCP - Model/dataset/paper search and documentation
  # ================================================================
  # Community stdio package: https://github.com/shreyaskarnik/huggingface-mcp-server
  # Requires: HF_TOKEN env var (from macOS Keychain via nix-darwin shell init).
  huggingface = {
    command = "uvx";
    args = [
      "--from"
      "huggingface-mcp-server==0.1.0"
      "--with"
      "huggingface-hub==1.12.0"
      "huggingface-mcp-server"
    ];
  };

  # Fabric MCP - community-maintained (ksylvan/fabric-mcp), exposes fabric
  # patterns as MCP tools. Requires fabric CLI setup (see modules/fabric/).
  # renovate: datasource=pypi depName=fabric-mcp
  fabric = {
    command = "uvx";
    args = [
      "--from"
      "fabric-mcp==1.1.0"
      "fabric-mcp"
      "--transport"
      "stdio"
    ];
  };

  # ================================================================
  # Obsidian - Integrated via Claude Code Plugin (not MCP)
  # ================================================================
  # The official Obsidian CLI (v1.8+, ships in Obsidian.app) provides 80+
  # commands. Integration uses the kepano/obsidian-skills Claude Code plugin
  # which teaches Claude to invoke the CLI via Bash. No MCP server needed.

  # ================================================================
  # Codex CLI - OpenAI coding agent MCP server
  # ================================================================
  codex = {
    command = "codex";
    args = [ "mcp-server" ];
  };

  # ================================================================
  # Database (disabled by default)
  # ================================================================

  postgresql = bunx [ "@modelcontextprotocol/server-postgres@0.6.2" ] // {
    disabled = true;
  };
  sqlite = bunx [ "@modelcontextprotocol/server-sqlite" ] // {
    disabled = true;
  }; # archived

  # ================================================================
  # Additional (disabled - specialized use cases)
  # ================================================================

  brave-search = bunx [ "@modelcontextprotocol/server-brave-search@0.6.2" ] // {
    disabled = true;
  };
  # Google Workspace - Gmail, Drive, Calendar integration.
  # Source: https://github.com/taylorwilsdon/google_workspace_mcp
  google-workspace = {
    command = "doppler-mcp";
    args = [
      "uvx"
      "--from"
      "google-workspace-mcp==2.0.1"
      "workspace-mcp"
      "--tools"
      "gmail"
      "drive"
      "calendar"
    ];
  };
  google-maps = bunx [ "@modelcontextprotocol/server-google-maps@0.6.2" ] // {
    disabled = true;
  };
  puppeteer = bunx [ "@modelcontextprotocol/server-puppeteer@2025.5.12" ] // {
    disabled = true;
  };
  slack = bunx [ "@modelcontextprotocol/server-slack@2025.4.25" ] // {
    disabled = true;
  };
  sentry = bunx [ "@modelcontextprotocol/server-sentry" ] // {
    disabled = true;
  }; # archived

  # ================================================================
  # Cribl MCP - OrbStack kubernetes-monitoring stack
  # ================================================================
  cribl = {
    type = "http";
    url = "http://localhost:30030/mcp";
  };

  # ================================================================
  # Bifrost AI Gateway - OrbStack kubernetes monitoring stack
  # ================================================================
  bifrost = {
    type = "http";
    url = "http://localhost:30080/mcp";
  };
}
