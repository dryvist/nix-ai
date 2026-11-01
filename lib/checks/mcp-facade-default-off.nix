# Compare the PR's default-off native MCP configuration with frozen output
# digests from the actual selector merge-base on the same system and inputs.
{
  pkgs,
  mkHmConfig,
  ...
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  gateway = "https://gateway.example.invalid";
  hmConfigDefaultOff = mkHmConfig [
    {
      programs.opencode.enable = true;
      programs.aiMcp.gatewayBaseUrl = gateway;
    }
  ];
  projection = import ./mcp-facade-default-off-projection.nix {
    inherit lib;
    codexMcpServers = hmConfigDefaultOff.config.programs.codex.generatedMcpServers;
    antigravityIdeMcpServers = hmConfigDefaultOff.config.programs.antigravity-ide.generatedMcpServers;
  } hmConfigDefaultOff;
  golden = import ./mcp-facade-default-off-goldens.nix;
  system = pkgs.stdenv.hostPlatform.system;
  actualJson = builtins.toJSON projection;
  actualSha256 = builtins.hashString "sha256" actualJson;
  actualBytes = builtins.stringLength actualJson;
  projectionsAndAssertionsPass = builtins.deepSeq hmConfigDefaultOff.config.assertions (
    builtins.deepSeq projection (
      builtins.all (assertion: assertion.assertion) hmConfigDefaultOff.config.assertions
    )
  );
in
{
  facade-canary-default-off-merge-base =
    assert
      projectionsAndAssertionsPass
      || throw "default-off Home Manager assertions failed or its MCP projection changed";
    assert
      builtins.hashString "sha256" (builtins.readFile ../../flake.lock) == golden.flakeLockSha256
      || throw "facade canary golden was captured from a different flake.lock";
    assert
      !hmConfigDefaultOff.config.programs.aiMcp.facadeCanary
      && builtins.all (selected: !selected) (
        builtins.attrValues hmConfigDefaultOff.config.programs.aiMcp.facadeCanaryClients
      )
      || throw "default-off merge-base comparison fixture enabled a facade selector";
    assert
      actualSha256 == golden.projections.${system}.sha256
      && actualBytes == golden.projections.${system}.bytes
      || throw "default-off MCP output differs from merge-base ${golden.baseCommit} on ${system}: ${actualSha256} (${toString actualBytes} bytes)";
    helpers.mkMarker "check-facade-canary-default-off-merge-base" "Default-off MCP maps, Claude attachments/approvals, and group MCP channels match the merge-base on ${system}";
}
