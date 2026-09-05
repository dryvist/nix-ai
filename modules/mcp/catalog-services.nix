# Shared MCP Servers Catalog — self-hosted services and specialized integrations
#
# Split out of catalog.nix, which holds the upstream/official servers and the
# shared helpers. Both halves are merged back together there, so this file is
# not imported directly; it takes the helpers it needs as arguments.

{
  bunx,
  codexMcp,
  dopplerRun,
  versions,
  homeDirectory,
}:

{
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
  google-workspace = dopplerRun {
    command = "uvx";
    args = [
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
  # Vikunja - self-hosted task management
  # ================================================================
  # Source: https://github.com/democratize-technology/vikunja-mcp (npm:
  # @democratize-technology/vikunja-mcp). Chosen over the newer one-author
  # forks: most contributors/stars by far and the widest tool surface (task/
  # project/label CRUD, batch import, webhooks) with rate limiting + circuit
  # breakers — built for autonomous agents. Requires VIKUNJA_URL (instance API
  # base, ends in /api/v1) and VIKUNJA_API_TOKEN — fetched at launch by the
  # server's own `doppler run` from the shared AI project.
  # Ships disabled — a consumer enables it deliberately once the Doppler
  # secrets exist for that machine.
  vikunja = codexMcp (dopplerRun {
    command = "bunx";
    args = [ "@democratize-technology/vikunja-mcp@${versions.vikunjaMcp}" ];
    disabled = true;
  });

  # ================================================================
  # Zammad - self-hosted help desk / ticketing (Zammad MCP, task #12)
  # ================================================================
  # Source: https://github.com/basher83/Zammad-MCP (not on PyPI/npm; launched
  # via uvx straight from the pinned git tag, entry point `mcp-zammad`). Covers
  # ticket/user/organization/attachment tools plus queue resources — the
  # surface the Hermes zammad-incidents loop drives. Requires ZAMMAD_URL
  # (instance API base, ends in /api/v1) and ZAMMAD_HTTP_TOKEN (a Zammad API
  # token) — fetched at launch by the server's own
  # `doppler run` from the shared AI project, same pattern as vikunja and
  # google-workspace. `uvx` must not inherit the Nix shell's
  # PYTHONPATH: the pinned server creates a Python 3.14 environment, while the
  # inherited 3.13 package path makes its native rpds extension fail at import.
  # Enabled in the shared profile. Only the non-secret project/config
  # selectors are in the Nix store; Zammad credentials stay in Doppler.
  zammad = codexMcp (dopplerRun {
    command = "env";
    args = [
      "-u"
      "PYTHONPATH"
      "-u"
      "PYTHONHOME"
      "uvx"
      "--from"
      "git+https://github.com/basher83/zammad-mcp.git@v${versions.zammadMcp}"
      "--with"
      versions.mcpSdkBound
      "mcp-zammad"
    ];
  });

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
  # OpenRouter - unified LLM API with free tier and paid models
  # ================================================================
  # Source: https://openrouter.ai/docs/guides/overview/mcp-server
  # Remote Streamable-HTTP endpoint. Uses the OPENROUTER_API_KEY env var
  # for authentication (inject via Doppler/Keychain at runtime).
  # Opt-in: ships disabled. Requires an OpenRouter account and API key.
  openrouter = {
    type = "http";
    url = "https://openrouter.ai/mcp";
    disabled = true;
  };

  # ================================================================
  # OpenWhispr - voice notes, transcriptions, and folders
  # ================================================================
  # Source: https://docs.openwhispr.com/integrations/mcp
  # Remote Streamable-HTTP endpoint. Requires a personal API key
  # (`owk_live_...`) in OPENWHISPR_API_KEY — inject at runtime (see
  # .env.example). Workspace keys are not supported. The CLI uses a
  # separate credential path (`openwhispr auth login` →
  # ~/.openwhispr/cli-config.json); MCP and CLI share the same key
  # material but not the delivery mechanism.
  # Opt-in: ships disabled. Requires an OpenWhispr account and API key.
  openwhispr = {
    type = "http";
    url = "https://mcp.openwhispr.com/mcp";
    headers.Authorization = "Bearer \${OPENWHISPR_API_KEY}";
    bearer_token_env_var = "OPENWHISPR_API_KEY";
    disabled = true;
  };

  # ================================================================
  # grep.app - literal code search across ~1M public GitHub repositories
  # ================================================================
  # Source: https://grep.app — remote Streamable-HTTP, stateless, keyless.
  # Exposes exactly one tool, `searchGitHub`, so clients surface it as
  # `mcp__grep__searchGitHub` (query, language[], repo, path, useRegexp,
  # matchCase, matchWholeWords).
  #
  # Enabled everywhere on purpose: finding how a problem was already solved is
  # the first rung of the native-first ladder, and a search tool that is only
  # present in some harnesses is one nobody learns to reach for. There is no
  # credential to scope and nothing to rotate; the only egress is the query
  # string, which the `github-code-search` skill governs.
  grep = {
    type = "http";
    url = "https://mcp.grep.app";
  };

  # ================================================================
  # Cribl MCP - OrbStack kubernetes-monitoring stack
  # ================================================================
  cribl = {
    type = "http";
    url = "http://localhost:30030/mcp";
  };

  # splunk/token-meter; programs.token-meter clears this once it installs.
  # It labels each answer with the agent runtime that asked, so every client
  # sends its own name rather than a value shared across the catalog.
  token-meter = {
    command = "${homeDirectory}/Library/Application Support/Token Meter/runtime/scripts/run-token-meter-mcp";
    clientNameEnv = "TOKEN_METER_CALLER";
    disabled = true;
  };
}
