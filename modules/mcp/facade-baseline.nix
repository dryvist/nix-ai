# Frozen MCP baseline for non-canary consumers (see README "Facade canary").
#
# Hand-written. Each key is a server name a non-canary consumer may reach;
# lib/checks/mcp.nix fails when any other name is reachable. Entries are removed
# when their server moves behind agent-facade. Names are never added here.
{
  apple-events = {
    owner = "nix-ai";
    expiry = "2027-01-31";
    cutover = "Vikunja 6201";
  };
  fabric = {
    owner = "nix-ai";
    expiry = "2027-01-31";
    cutover = "Vikunja 6201";
  };
  grep = {
    owner = "nix-ai";
    expiry = "2027-01-31";
    cutover = "Vikunja 6201";
  };
  splunk = {
    owner = "nix-ai";
    expiry = "2027-01-31";
    cutover = "Vikunja 6201";
  };
  splunkbase = {
    owner = "nix-ai";
    expiry = "2027-01-31";
    cutover = "Vikunja 6201";
  };
  time = {
    owner = "nix-ai";
    expiry = "2027-01-31";
    cutover = "Vikunja 6201";
  };
  zammad = {
    owner = "nix-ai";
    expiry = "2027-01-31";
    cutover = "Vikunja 6201";
  };
}
