# Shared MCP Servers Catalog
#
# Portable MCP server definitions using standard commands.
# Uses bunx for npm packages and uvx for Python packages.
#
# Official MCP Servers: https://github.com/modelcontextprotocol/servers
#
# Servers requiring API keys read them from environment variables. Use your
# secrets manager (Doppler, Keychain, etc.) to inject env vars.

{
  homeDirectory,
  pkgs,
  gatewayBaseUrl ? null,
}:
let
  # Remote route on the shared agentgateway MCP layer. Disabled until a
  # consumer sets programs.aiMcp.gatewayBaseUrl — the base URL names private
  # topology and is never a literal here (see modules/mcp/default.nix).
  gatewayRoute =
    path: extra:
    {
      type = "http";
      url = if gatewayBaseUrl == null then null else "${gatewayBaseUrl}${path}";
      disabled = gatewayBaseUrl == null;
    }
    // extra;
  # Python MCP servers built as Nix derivations rather than launched through
  # uvx. A live uvx process holds a shared lock on the uv cache for its whole
  # lifetime, which is what stopped `uv cache prune` from ever succeeding —
  # see modules/mcp/packages.nix.
  mcpPkgs = import ./packages.nix { inherit pkgs; };
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
  # Doppler-backed launch: prefix a server's command with `doppler run` for
  # the project/config named in vars/ai-stack.nix. Secrets are fetched by the
  # child process at launch; only the non-secret selectors are in the store.
  dopplerRun =
    server:
    server
    // {
      command = "${pkgs.doppler}/bin/doppler";
      args = [
        "run"
        "-p"
        dopplerSelectors.project
        "-c"
        dopplerSelectors.config
        "--"
        server.command
      ]
      ++ (server.args or [ ]);
    };
  dopplerSelectors = (import ../../vars/ai-stack.nix).doppler;

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
  # memory: cross-agent vector memory via the gateway's mcp-server-qdrant
  # sidecar. Replaces the local knowledge-graph server (11 calls all-time per
  # Splunk, and duplicated the file-based MEMORY.md system) with the same
  # capability every harness already gets when a host sets gatewayBaseUrl.
  memory = gatewayRoute "/memory" { };
  time = codexMcp {
    command = "${mcpPkgs.mcp-server-time}/bin/mcp-server-time";
    args = [ ];
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

  # Context7 - real-time documentation retrieval, via the gateway route
  # instead of a per-harness bunx process (fixes duplicate local MCP spawns).
  # Claude additionally has the context7 *plugin* (mcp__plugin_context7_context7,
  # 569x vs 48x per Splunk for this entry); the two coexist under different
  # names. Cursor/OpenCode/Codex, which have no plugin, get context7 only
  # from this route.
  context7 = gatewayRoute "/context7" { };

  # Docs-RAG search over the homelab documentation index, via the gateway.
  docs = gatewayRoute "/docs" { };

  # ================================================================
  # HuggingFace MCP - Model/dataset/paper search and documentation
  # ================================================================
  # Community stdio package: https://github.com/shreyaskarnik/huggingface-mcp-server
  # Requires: HF_TOKEN — inject at runtime (see .env.example).
  huggingface = codexMcp {
    command = "${mcpPkgs.huggingface-mcp-server}/bin/huggingface-mcp-server";
    args = [ ];
    # The hosted connector already serves the same Hub tools; a second copy
    # only doubles the schema every session pays for.
    disabled = true;
  };

  # Fabric MCP - community-maintained (ksylvan/fabric-mcp), exposes fabric
  # patterns as MCP tools. Requires fabric CLI setup (see modules/fabric/).
  fabric = codexMcp {
    command = "${mcpPkgs.fabric-mcp}/bin/fabric-mcp";
    args = [
      "--transport"
      "stdio"
    ];
  };

  # Splunk MCP via the gateway. The gateway passes the caller's Authorization
  # header straight through to the Splunk backend (auth: passthrough), so the
  # bearer token here is a Splunk-minted mcp_token (GET /services/mcp_token),
  # not an OpenBao credential — replaces the local splunk-mcp-connect
  # stdio launcher, which never got a working secret-zero wired up.
  splunk = gatewayRoute "/splunk" {
    headers.Authorization = "Bearer \${SPLUNK_MCP_TOKEN}";
    bearer_token_env_var = "SPLUNK_MCP_TOKEN";
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
    dopplerRun
    versions
    ;
}
