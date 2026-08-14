# Shared MCP Servers Catalog
#
# Portable MCP server definitions using standard commands.
# Uses bunx for npm packages and uvx for Python packages.
#
# Official MCP Servers: https://github.com/modelcontextprotocol/servers
#
# Servers requiring API keys read them from environment variables. Use your
# secrets manager (Doppler, Keychain, etc.) to inject env vars.

{ homeDirectory }:
let
  # bunx helper: command-only args for MCP server definitions.
  bunx = args: {
    command = "bunx";
    inherit args;
  };

  codexMcp =
    server:
    server
    // {
      startup_timeout_sec = 300;
      tool_timeout_sec = 300;
    };
  dopplerEnv = [
    "AI_DOPPLER_PROJECT"
    "AI_DOPPLER_CONFIG"
  ];

  # Version pins live in lib/versions.nix, where the org-wide Renovate
  # customManager regex tracks the annotations; refer to them directly.
  versions = import ../../lib/versions.nix;
in
{
  # ================================================================
  # Official Anthropic MCP Servers
  # ================================================================
  # Archived servers remain unpinned unless a maintained replacement exists.

  everything = bunx [ "@modelcontextprotocol/server-everything@${versions.mcpEverything}" ];
  fetch = bunx [ "@modelcontextprotocol/server-fetch" ]; # archived
  filesystem = bunx [ "@modelcontextprotocol/server-filesystem@${versions.mcpFilesystem}" ];
  git = bunx [ "@modelcontextprotocol/server-git" ]; # archived
  # memory: DISABLED — the file-based MEMORY.md system is the real memory store;
  # this knowledge-graph server is redundant (11 calls all-time per Splunk).
  memory = bunx [ "@modelcontextprotocol/server-memory@${versions.mcpMemory}" ] // {
    disabled = true;
  };
  time = codexMcp {
    command = "uvx";
    args = [
      "--from"
      "mcp-server-time==${versions.mcpServerTime}"
      "--with"
      versions.mcpSdkBound
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
  aws = bunx [ "@modelcontextprotocol/server-aws-kb-retrieval@${versions.mcpAws}" ] // {
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
  context7 = bunx [ "@upstash/context7-mcp@${versions.context7Mcp}" ] // {
    disabled = true;
  };

  # ================================================================
  # HuggingFace MCP - Model/dataset/paper search and documentation
  # ================================================================
  # Community stdio package: https://github.com/shreyaskarnik/huggingface-mcp-server
  # Requires: HF_TOKEN — inject at runtime (see .env.example).
  huggingface = codexMcp {
    command = "uvx";
    args = [
      "--from"
      "huggingface-mcp-server==${versions.hfMcpServer}"
      "--with"
      "huggingface-hub==${versions.huggingfaceHub}"
      "--with"
      versions.mcpSdkBound
      "huggingface-mcp-server"
    ];
  };

  # Fabric MCP - community-maintained (ksylvan/fabric-mcp), exposes fabric
  # patterns as MCP tools. Requires fabric CLI setup (see modules/fabric/).
  fabric = codexMcp {
    command = "uvx";
    args = [
      "--from"
      "fabric-mcp==${versions.fabricMcp}"
      "fabric-mcp"
      "--transport"
      "stdio"
    ];
  };

  # Splunk MCP via OpenBao. The helper authenticates with an ambient-env
  # AppRole and injects the canonical connection only into its MCP child
  # process.
  splunk = codexMcp {
    command = "splunk-mcp-connect";
    # Codex forwards stdio-server environment variables only when they are
    # explicitly declared. Keep the OpenBao bootstrap scoped to this launcher.
    env_vars = [
      "BAO_ADDR"
      "AI_READONLY_ROLE_ID"
      "AI_READONLY_SECRET_ID"
      "SPLUNK_MCP_OPENBAO_PATH"
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
  apple-events = codexMcp (bunx [ "mcp-server-apple-events@${versions.mcpAppleEvents}" ]);

}
// import ./catalog-services.nix {
  inherit
    bunx
    codexMcp
    dopplerEnv
    versions
    homeDirectory
    ;
}
