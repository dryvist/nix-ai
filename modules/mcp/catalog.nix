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
  # Package version pins — sourced from lib/versions.nix
  # ================================================================

  mcpEverythingVersion = versions.mcpEverything;
  context7McpVersion = versions.context7Mcp;
  mcpFilesystemVersion = versions.mcpFilesystem;
  mcpMemoryVersion = versions.mcpMemory;
  mcpAwsVersion = versions.mcpAws;
  mcpPostgresVersion = versions.mcpPostgres;
  mcpBraveSearchVersion = versions.mcpBraveSearch;
  mcpGoogleMapsVersion = versions.mcpGoogleMaps;
  mcpPuppeteerVersion = versions.mcpPuppeteer;
  mcpSlackVersion = versions.mcpSlack;
  mcpAppleEventsVersion = versions.mcpAppleEvents;
  mcpServerTimeVersion = versions.mcpServerTime;
  hfMcpServerVersion = versions.hfMcpServer;
  fabricMcpVersion = versions.fabricMcp;
  gwsMcpVersion = versions.gwsMcp;
  unifiMcpServerVersion = versions.unifiMcpServer;
in
{
  # ================================================================
  # Official Anthropic MCP Servers
  # ================================================================
  # Version pins live in lib/versions.nix where the Renovate annotations are
  # tracked by the org-wide customManager regex; the let-bindings above are
  # plain references. Archived servers remain unpinned unless a maintained
  # replacement exists.

  everything = bunx [ "@modelcontextprotocol/server-everything@${mcpEverythingVersion}" ];
  fetch = bunx [ "@modelcontextprotocol/server-fetch" ]; # archived
  filesystem = bunx [ "@modelcontextprotocol/server-filesystem@${mcpFilesystemVersion}" ];
  git = bunx [ "@modelcontextprotocol/server-git" ]; # archived
  # memory: DISABLED — the file-based MEMORY.md system is the real memory store;
  # this knowledge-graph server is redundant (11 calls all-time per Splunk).
  memory = bunx [ "@modelcontextprotocol/server-memory@${mcpMemoryVersion}" ] // {
    disabled = true;
  };
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
  aws = bunx [ "@modelcontextprotocol/server-aws-kb-retrieval@${mcpAwsVersion}" ] // {
    disabled = true;
  }; # Requires: AWS credentials; 0 calls in 3 months of history

  # ================================================================
  # Native nixpkgs packages
  # ================================================================

  # Terraform - terraform-mcp-server from nixpkgs.
  terraform = {
    command = "terraform-mcp-server";
  };

  # GitHub - github-mcp-server from nixpkgs.
  # Requires: GITHUB_PERSONAL_ACCESS_TOKEN — inject at runtime (see .env.example).
  github = {
    command = "github-mcp-server";
    disabled = true;
  };

  # ================================================================
  # Third-party npm packages
  # ================================================================

  # Context7 - real-time documentation retrieval MCP server
  # DISABLED — duplicates the context7 *plugin*'s MCP (569x vs 48x per Splunk).
  # Keep the plugin (mcp__plugin_context7_context7); drop this catalog server.
  context7 = bunx [ "@upstash/context7-mcp@${context7McpVersion}" ] // {
    disabled = true;
  };

  # ================================================================
  # HuggingFace MCP - Model/dataset/paper search and documentation
  # ================================================================
  # Community stdio package: https://github.com/shreyaskarnik/huggingface-mcp-server
  # Requires: HF_TOKEN — inject at runtime (see .env.example).
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
  # Apple Events - native macOS Reminders + Calendar via EventKit
  # ================================================================
  # Source: https://github.com/FradSer/mcp-server-apple-events
  # First call triggers macOS TCC prompts for Reminders + Calendar.
  apple-events = bunx [ "mcp-server-apple-events@${mcpAppleEventsVersion}" ];

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
  # DISABLED but kept defined — "available in case we ever need it". Was leaking
  # enabled (no flag) despite 0 use; this restores the intended off state.
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
    disabled = true;
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
  # UniFi Network - local UniFi gateway/controller management
  # ================================================================
  # Source: https://github.com/enuno/unifi-mcp-server (PyPI: unifi-mcp-server)
  # stdio server that talks to the UniFi gateway on the LAN. Requires (inject at
  # runtime — see .env.example): UNIFI_API_KEY (secret, unifi.ui.com) and
  # UNIFI_LOCAL_HOST (gateway IP, e.g. 192.168.0.1 — real value is topology; keep
  # it in the no-password secret store, never committed). UNIFI_API_TYPE is
  # non-secret config and is pinned to "local" here.
  unifi = {
    command = "uvx";
    args = [
      "--from"
      "unifi-mcp-server==${unifiMcpServerVersion}"
      "unifi-mcp-server"
    ];
    env = {
      UNIFI_API_TYPE = "local";
    };
    # Opt-in: ships disabled. It needs a reachable LAN gateway and personal
    # credentials, so a consumer enables it deliberately.
    disabled = true;
  };

  # ================================================================
  # Monarch Money - personal finance (official hosted MCP connector)
  # ================================================================
  # Source: https://help.monarch.com/hc/en-us/articles/50207234679956
  # Remote Streamable-HTTP endpoint. Auth is browser OAuth handled by the MCP
  # client on first connect — no token or header is stored in this config.
  monarch = {
    type = "http";
    url = "https://api.monarch.com/mcp";
    # Opt-in: ships disabled. It requires a personal Monarch account and
    # browser OAuth, so a consumer enables it deliberately.
    disabled = true;
  };

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
