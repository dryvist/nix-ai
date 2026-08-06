# Optional MCP servers — defined but shipped disabled.
#
# Split out of ./catalog.nix at the seam that file already marked, for the
# per-file byte cap in .file-size.yml. catalog.nix reached 12,268 of its 12,288
# error limit, so the next entry of any kind failed CI; .file-size.yml's own
# header says to split rather than declare an extended limit.
#
# Every entry here is `disabled = true` — kept defined so a consumer can enable
# one deliberately, inert in the shared profile until then. The attrset merges
# straight back into the catalog, so server names and behaviour are unchanged.
{ bunx, versions }:
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
}
