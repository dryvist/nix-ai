# Antigravity Extension Management
#
# Deploys Nix-managed extensions to ~/.gemini/antigravity-cli/extensions/<name>/.
# Each extension gets a antigravity-extension.json manifest and optional commands.
{ config, lib, ... }:

let
  cfg = config.programs.antigravity-cli;
  facadeCanarySelected =
    config.programs.aiMcp.facadeCanary || config.programs.aiMcp.facadeCanaryClients.antigravity-cli;

  # Generate file entries for a single extension
  mkExtensionFiles =
    name: ext:
    let
      manifest = builtins.toJSON {
        inherit name;
        inherit (ext) description;
        # Extension manifests are another MCP entry point for this client.
        mcpServers = if facadeCanarySelected then { } else ext.mcpServers;
      };
      commandFiles = lib.mapAttrs' (
        cmdName: path:
        lib.nameValuePair ".gemini/antigravity-cli/extensions/${name}/commands/${cmdName}.toml" {
          source = path;
          force = true;
        }
      ) ext.commands;
    in
    {
      ".gemini/antigravity-cli/extensions/${name}/antigravity-extension.json" = {
        text = manifest;
        force = true;
      };
    }
    // commandFiles;
in
{
  config = lib.mkIf cfg.enable {
    home.file = lib.concatMapAttrs mkExtensionFiles cfg.extensions;
  };
}
