# Gemini Extension Management
#
# Deploys Nix-managed extensions to ~/.gemini/extensions/<name>/.
# Each extension gets a gemini-extension.json manifest and optional commands.
{ config, lib, ... }:

let
  cfg = config.programs.gemini;

  # Generate file entries for a single extension
  mkExtensionFiles =
    name: ext:
    let
      manifest = builtins.toJSON {
        inherit name;
        inherit (ext) description;
        inherit (ext) mcpServers;
      };
      commandFiles = lib.mapAttrs' (
        cmdName: path:
        lib.nameValuePair ".gemini/extensions/${name}/commands/${cmdName}.toml" {
          source = path;
          force = true;
        }
      ) ext.commands;
    in
    {
      ".gemini/extensions/${name}/gemini-extension.json" = {
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
