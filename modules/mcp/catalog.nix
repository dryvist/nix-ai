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
  time = {
    command = "uvx";
    args = [
      "--from"
      "mcp-server-time==${versions.mcpServerTime}"
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
  huggingface = {
    command = "uvx";
    args = [
      "--from"
      "huggingface-mcp-server==${versions.hfMcpServer}"
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
      "fabric-mcp==${versions.fabricMcp}"
      "fabric-mcp"
      "--transport"
      "stdio"
    ];
  };

  # Splunk MCP via OpenBao. The helper authenticates with an ambient-env
  # AppRole and injects the canonical connection only into its MCP child
  # process.
  splunk = {
    command = "splunk-mcp-connect";
    # Codex inherits only explicitly listed ambient variables for each stdio
    # server. Keep the AppRole bootstrap narrowly scoped to this launcher.
    env_vars = [
      "BAO_ADDR"
      "AI_READONLY_ROLE_ID"
      "AI_READONLY_SECRET_ID"
      "SPLUNK_MCP_OPENBAO_PATH"
    ];
    startup_timeout_sec = 300;
    tool_timeout_sec = 300;
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
  apple-events = bunx [ "mcp-server-apple-events@${versions.mcpAppleEvents}" ];

  # ================================================================
  # Database (disabled by default)
  # ================================================================

  postgresql = bunx [ "@modelcontextprotocol/server-postgres@${versions.mcpPostgres}" ] // {
    disabled = true;
  };
  sqlite = bunx [ "@modelcontextprotocol/server-sqlite" ] // {
    disabled = true;
  }; # archived

  # ================================================================
  # Additional (disabled - specialized use cases)
  # ================================================================

  brave-search = bunx [ "@modelcontextprotocol/server-brave-search@${versions.mcpBraveSearch}" ] // {
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
      "google-workspace-mcp==${versions.gwsMcp}"
      "workspace-mcp"
      "--tools"
      "gmail"
      "drive"
      "calendar"
    ];
    disabled = true;
  };
  google-maps = bunx [ "@modelcontextprotocol/server-google-maps@${versions.mcpGoogleMaps}" ] // {
    disabled = true;
  };
  puppeteer = bunx [ "@modelcontextprotocol/server-puppeteer@${versions.mcpPuppeteer}" ] // {
    disabled = true;
  };
  slack = bunx [ "@modelcontextprotocol/server-slack@${versions.mcpSlack}" ] // {
    disabled = true;
  };
  sentry = bunx [ "@modelcontextprotocol/server-sentry" ] // {
    disabled = true;
  }; # archived

  # ================================================================
  # Vikunja - self-hosted task management (docs-starlight#141)
  # ================================================================
  # Source: https://github.com/democratize-technology/vikunja-mcp (npm:
  # @democratize-technology/vikunja-mcp). Chosen over the newer one-author
  # forks: most contributors/stars by far and the widest tool surface (task/
  # project/label CRUD, batch import, webhooks) with rate limiting + circuit
  # breakers — built for autonomous agents. Requires VIKUNJA_URL (instance API
  # base, ends in /api/v1) and VIKUNJA_API_TOKEN (a tk_ service-account token,
  # svc-mcp-rw tier) — injected at launch by doppler-mcp from the configured
  # Doppler project, same pattern as google-workspace. Canonical token home is the secrets
  # engine's apps/vikunja secret (promoted from the app role's SOPS mint).
  # Ships disabled — a consumer enables it deliberately once the Doppler
  # secrets exist for that machine.
  vikunja = {
    command = "doppler-mcp";
    args = [
      "bunx"
      "@democratize-technology/vikunja-mcp@${versions.vikunjaMcp}"
    ];
    # Codex needs the Doppler wrapper configuration forwarded explicitly.
    env_vars = [
      "AI_DOPPLER_PROJECT"
      "AI_DOPPLER_CONFIG"
    ];
    startup_timeout_sec = 300;
    tool_timeout_sec = 300;
    disabled = true;
  };

  # ================================================================
  # Zammad - self-hosted help desk / ticketing (Zammad MCP, task #12)
  # ================================================================
  # Source: https://github.com/basher83/Zammad-MCP (not on PyPI/npm; launched
  # via uvx straight from the pinned git tag, entry point `mcp-zammad`). Covers
  # ticket/user/organization/attachment tools plus queue resources — the
  # surface the Hermes zammad-incidents loop drives. Requires ZAMMAD_URL
  # (instance API base, ends in /api/v1) and ZAMMAD_HTTP_TOKEN (a Zammad API
  # token) — injected at launch by doppler-mcp from the configured Doppler
  # project, same pattern as vikunja/google-workspace. Canonical token home is the secrets
  # engine's secret/ai/mcp/zammad (ZAMMAD_MCP_URL + ZAMMAD_MCP_TOKEN fields).
  # Enabled in the shared profile. Its Doppler wrapper receives only the
  # project/config selectors from Codex; Zammad credentials stay in Doppler.
  zammad = {
    command = "doppler-mcp";
    args = [
      "uvx"
      "--from"
      "git+https://github.com/basher83/zammad-mcp.git@v${versions.zammadMcp}"
      "mcp-zammad"
    ];
    env_vars = [
      "AI_DOPPLER_PROJECT"
      "AI_DOPPLER_CONFIG"
    ];
    startup_timeout_sec = 300;
    tool_timeout_sec = 300;
  };

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
      "unifi-mcp-server==${versions.unifiMcpServer}"
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
}
