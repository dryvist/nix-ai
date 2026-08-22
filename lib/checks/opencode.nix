# OpenCode module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.opencode;
  homeFiles = hmConfig.config.home.file;
in
{
  # Verify all expected OpenCode option paths exist.
  opencode-options-regression = helpers.mkOptionsRegression {
    label = "OpenCode";
    checkName = "check-opencode-options-regression";
    inherit cfg;
    expectedOptions = [
      "commandDirs"
      "configDir"
      "enable"
      "excludedMcpServers"
      "extraSettings"
      "mcpServerNames"
    ];
  };

  # Verify evaluated config values match expected defaults.
  opencode-defaults-regression = helpers.mkDefaultsRegression {
    label = "OpenCode";
    checkName = "check-opencode-defaults-regression";
    checks = [
      {
        name = "opencode.enable";
        actual = cfg.enable;
        expected = true;
      }
      {
        name = "opencode.configDir";
        actual = cfg.configDir;
        expected = ".config/opencode";
      }
    ];
  };

  # OpenCode is the only MCP renderer that writes its config as a plain
  # store symlink rather than merging into a mutable file, so a schema slip
  # here lands verbatim in the user's config with nothing to correct it.
  # `mcp` (not `mcpServers`) is opencode's key, and each server is tagged
  # local/remote rather than stdio/http.
  opencode-config-json =
    let
      configPath = "${cfg.configDir}/opencode.json";
      hasConfig = builtins.hasAttr configPath homeFiles;
    in
    assert hasConfig || throw "OpenCode config not deployed at ${configPath}";
    pkgs.runCommand "check-opencode-config-json"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        config=${homeFiles.${configPath}.source}

        jq -e '.mcp | type == "object"' "$config" > /dev/null \
          || { echo "opencode.json is missing the .mcp object" >&2; exit 1; }

        # Every server must carry a type opencode understands. An untyped or
        # foreign-typed entry is silently ignored at load, which is
        # indistinguishable from the server simply never being configured.
        bad=$(jq -r '.mcp | to_entries[]
          | select((.value.type // "") | inside("local remote") | not)
          | .key' "$config")
        if [ -n "$bad" ]; then
          echo "opencode MCP servers with a non-local/remote type: $bad" >&2
          exit 1
        fi

        touch $out
      '';
}
