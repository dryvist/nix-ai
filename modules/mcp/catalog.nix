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
  # bunx helper: command-only args for MCP server definitions.
  bunx = args: {
    command = "bunx";
    inherit args;
  };

  versions = import ../../lib/versions.nix;

  # ================================================================
  # Package version pins — Renovate tracks these via annotation comments
  # ================================================================

  # renovate: datasource=npm depName=@modelcontextprotocol/server-everything
  mcpEverythingVersion = "2026.1.26";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-filesystem
  mcpFilesystemVersion = "2026.1.14";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-memory
  mcpMemoryVersion = "2026.1.26";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-aws-kb-retrieval
  mcpAwsVersion = "0.6.2";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-postgres
  mcpPostgresVersion = "0.6.2";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-brave-search
  mcpBraveSearchVersion = "0.6.2";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-google-maps
  mcpGoogleMapsVersion = "0.6.2";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-puppeteer
  mcpPuppeteerVersion = "2025.5.12";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-slack
  mcpSlackVersion = "2025.4.25";

  # renovate: datasource=pypi depName=mcp-server-time
  mcpServerTimeVersion = "2026.1.26";
  # renovate: datasource=pypi depName=huggingface-mcp-server
  hfMcpServerVersion = "0.1.0";
  # renovate: datasource=pypi depName=fabric-mcp
  fabricMcpVersion = "1.1.0";
  # renovate: datasource=pypi depName=google-workspace-mcp
  gwsMcpVersion = "2.0.1";
in
{
  # ================================================================
  # Official Anthropic MCP Servers
  # ================================================================
  # Versions are let-bound above with Renovate annotation comments for regex tracking.
  # Archived servers remain unpinned unless a maintained replacement exists.

  everything = bunx [ "@modelcontextprotocol/server-everything@${mcpEverythingVersion}" ];
  fetch = bunx [ "@modelcontextprotocol/server-fetch" ]; # archived
  filesystem = bunx [ "@modelcontextprotocol/server-filesystem@${mcpFilesystemVersion}" ];
  git = bunx [ "@modelcontextprotocol/server-git" ]; # archived
  memory = bunx [ "@modelcontextprotocol/server-memory@${mcpMemoryVersion}" ];
  sequentialthinking = bunx [ "@modelcontextprotocol/server-sequential-thinking" ]; # archived
  time = {
    command = "uvx";
    args = [
      "--from"
      "mcp-server-time==${mcpServerTimeVersion}"
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
  aws = bunx [ "@modelcontextprotocol/server-aws-kb-retrieval@${mcpAwsVersion}" ]; # Requires: AWS credentials

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
      "huggingface-mcp-server==${hfMcpServerVersion}"
      "--with"
      "huggingface-hub==${versions.huggingfaceHub}"
      "huggingface-mcp-server"
    ];
  };

  # Fabric MCP - community-maintained (ksylvan/fabric-mcp), exposes fabric
  # patterns as MCP tools. Requires fabric CLI setup (see modules/fabric/).
  fabric = {
    command = "uvx";
    args = [
      "--from"
      "fabric-mcp==${fabricMcpVersion}"
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

  postgresql = bunx [ "@modelcontextprotocol/server-postgres@${mcpPostgresVersion}" ] // {
    disabled = true;
  };
  sqlite = bunx [ "@modelcontextprotocol/server-sqlite" ] // {
    disabled = true;
  }; # archived

  # ================================================================
  # Additional (disabled - specialized use cases)
  # ================================================================

  brave-search = bunx [ "@modelcontextprotocol/server-brave-search@${mcpBraveSearchVersion}" ] // {
    disabled = true;
  };
  # Google Workspace - Gmail, Drive, Calendar integration.
  # Source: https://github.com/taylorwilsdon/google_workspace_mcp
  google-workspace = {
    command = "doppler-mcp";
    args = [
      "uvx"
      "--from"
      "google-workspace-mcp==${gwsMcpVersion}"
      "workspace-mcp"
      "--tools"
      "gmail"
      "drive"
      "calendar"
    ];
  };
  google-maps = bunx [ "@modelcontextprotocol/server-google-maps@${mcpGoogleMapsVersion}" ] // {
    disabled = true;
  };
  puppeteer = bunx [ "@modelcontextprotocol/server-puppeteer@${mcpPuppeteerVersion}" ] // {
    disabled = true;
  };
  slack = bunx [ "@modelcontextprotocol/server-slack@${mcpSlackVersion}" ] // {
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
