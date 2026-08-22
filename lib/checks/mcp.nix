# Shared MCP profile regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.aiMcp;
  expectedGlobalServers = [
    "codex"
    "fabric"
    "huggingface"
    "splunk"
    "time"
    "zammad"
  ]
  ++ pkgs.lib.optional pkgs.stdenv.isDarwin "apple-events";
  missingGlobalServers = builtins.filter (
    name: !(builtins.elem name cfg.enabledServerNames)
  ) expectedGlobalServers;
  rendererNames = {
    claude = builtins.attrNames hmConfig.config.programs.claude.mcpServers;
    codex = hmConfig.config.programs.codex.mcpServerNames;
    antigravity-cli = hmConfig.config.programs.antigravity-cli.mcpServerNames;
    antigravity-ide = hmConfig.config.programs.antigravity-ide.mcpServerNames;
    qwen-code = hmConfig.config.programs.qwen-code.mcpServerNames;
    opencode = hmConfig.config.programs.opencode.mcpServerNames;
    cursor = hmConfig.config.programs.cursor.mcpServerNames;
  };
  rendererMismatches = builtins.filter (name: rendererNames.${name} != cfg.enabledServerNames) (
    builtins.attrNames rendererNames
  );
  codexLaunchContracts = {
    time = { };
    huggingface = { };
    fabric = { };
    apple-events = { };
    splunk = {
      env_vars = [
        "AI_DOPPLER_PROJECT"
        "AI_DOPPLER_CONFIG"
      ];
    };
    vikunja = {
      env_vars = [
        "AI_DOPPLER_PROJECT"
        "AI_DOPPLER_CONFIG"
      ];
    };
    zammad = {
      env_vars = [
        "AI_DOPPLER_PROJECT"
        "AI_DOPPLER_CONFIG"
      ];
    };
  };
  # Remote servers with nothing to deliver — the legitimate exception to the
  # rule below. Each entry needs a reason; "it fails the check" is not one.
  credentiallessRemoteServers = [
    "grep" # public, stateless, keyless — nothing to authenticate
    "cribl" # loopback endpoint on the local monitoring stack, unauthenticated
    "monarch" # browser OAuth negotiated by the client on first connect
  ];
  carriesNoCredential =
    server:
    builtins.all (held: held) [
      (server.headers == { })
      (server.http_headers == { })
      (server.env_http_headers == { })
      (server.bearer_token_env_var == null)
      (server.oauth_resource == null)
    ];
  remoteAuthGaps = builtins.filter (
    name:
    let
      server = cfg.servers.${name};
    in
    builtins.all (held: held) [
      (server.url != null)
      (!(builtins.elem name credentiallessRemoteServers))
      (carriesNoCredential server)
    ]
  ) (builtins.attrNames cfg.servers);

  codexLaunchContractMismatches = builtins.filter (
    name:
    let
      expected = codexLaunchContracts.${name};
      actual = cfg.servers.${name};
    in
    actual.startup_timeout_sec != 300
    || actual.tool_timeout_sec != 300
    || (expected ? env_vars && actual.env_vars != expected.env_vars)
  ) (builtins.attrNames codexLaunchContracts);
in
{
  shared-mcp-global-profile =
    assert
      missingGlobalServers == [ ]
      || throw "Shared MCP profile missing global servers: ${builtins.toJSON missingGlobalServers}; actual=${builtins.toJSON cfg.enabledServerNames}";
    helpers.mkMarker "check-shared-mcp-global-profile" "Shared MCP profile includes ${toString (builtins.length expectedGlobalServers)} expected global servers";

  shared-mcp-renderer-parity =
    assert
      rendererMismatches == [ ]
      || throw "MCP renderer parity mismatch: ${builtins.toJSON rendererMismatches}; shared=${builtins.toJSON cfg.enabledServerNames}; renderers=${builtins.toJSON rendererNames}";
    helpers.mkMarker "check-shared-mcp-renderer-parity" "Shared MCP renderer parity verified for Claude, Codex, Antigravity CLI/IDE, Qwen, OpenCode, and Cursor";

  # Reversed deliberately. This previously asserted the opposite — that splunk
  # launched `splunk-mcp-connect` directly, "without Doppler wiring" — which
  # made the launcher depend on four OpenBao bootstrap vars being ambient in
  # whatever process started the harness. That only holds in an interactive
  # zsh, so the server could never start from a GUI or launchd launch, and the
  # keychain loader that supplied them failed silently when an item was absent.
  # Doppler now fetches secret-zero at launch; splunk-mcp-connect still does the
  # OpenBao AppRole login and remains the only thing that sees the credential.
  splunk-mcp-canonical-launcher =
    assert
      cfg.servers.splunk.command == "doppler-mcp" && cfg.servers.splunk.args == [ "splunk-mcp-connect" ]
      || throw "Splunk MCP must launch through doppler-mcp -> splunk-mcp-connect: ${builtins.toJSON cfg.servers.splunk}";
    helpers.mkMarker "check-splunk-mcp-canonical-launcher" "Splunk MCP uses the OpenBao launcher behind Doppler secret-zero injection";

  # A remote server reached over a bare URL can only carry a credential through
  # a client-specific field, and none of those render identically across all
  # seven normalizers — `bearer_token_env_var` is Codex-only, and a `${VAR}`
  # header is expanded by some clients and passed through literally by others.
  # So a remote server that needs auth is declared as a stdio `mcp-remote`
  # proxy command instead, which every client launches the same way.
  #
  # This catches the shape that let `openrouter` ship broken in all seven
  # clients: a bare `type = "http"` URL whose comment claimed API-key auth
  # while the entry carried no credential field at all.
  shared-mcp-remote-auth-declared =
    assert
      remoteAuthGaps == [ ]
      || throw "Remote MCP servers declare a URL but no credential (add headers/bearer_token_env_var/oauth_resource, launch via the mcp-remote stdio proxy, or add to credentiallessRemoteServers): ${builtins.toJSON remoteAuthGaps}";
    helpers.mkMarker "check-shared-mcp-remote-auth-declared" "Every credentialed remote MCP server declares how its credential is delivered";

  codex-mcp-launch-contract =
    assert
      codexLaunchContractMismatches == [ ]
      || throw "Codex MCP launch contract mismatch: ${builtins.toJSON codexLaunchContractMismatches}";
    helpers.mkMarker "check-codex-mcp-launch-contract" "Codex MCP servers have scoped environment forwarding and 300-second startup/tool timeouts";

  splunk-mcp-openbao-wrapper =
    pkgs.runCommand "check-splunk-mcp-openbao-wrapper"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        ${pkgs.bash}/bin/bash ${../../modules/mcp/tests/splunk-mcp-connect.sh} \
          ${../../modules/mcp/scripts/splunk-mcp-connect.sh}
        touch $out
      '';
}
