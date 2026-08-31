# Antigravity CLI Configuration Module
#
# Declarative configuration for Google Antigravity CLI.
# Generates settings.json with shared MCP servers, permissions, commands,
# extensions, and folder trust.
#
# CRITICAL - tools.allowed vs tools.core:
# Per the official Antigravity CLI schema:
# - tools.allowed = "Tool names that bypass the confirmation dialog" (AUTO-APPROVE)
# - tools.core = "Allowlist to RESTRICT built-in tools to a specific set" (LIMITS usage!)
# Always use tools.allowed for auto-approval, NEVER tools.core!
#
# Features:
# - Shared MCP server definitions (normalized for Antigravity format)
# - Auto-generated custom commands from agentsmd
# - Extension management (~/.gemini/antigravity-cli/extensions/)
# - settings.json deep-merge activation (preserves auth tokens)
{
  config,
  lib,
  pkgs,
  llm-agents,
  ...
}:

let
  cfg = config.programs.antigravity-cli;
  agyPackage = llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli;
in
{
  # home-manager release-26.05 gained its own programs.antigravity-cli
  # module (added between 4eb4fec and d899b01); its `commands` option is
  # typed attrsOf (submodule str) and cannot coexist with this module's
  # nested commands.{fromFlakeInputs,local} options. This module predates
  # and supersedes the upstream one — shadow it.
  disabledModules = [ "programs/antigravity-cli.nix" ];

  imports = [
    ./options.nix
    ./settings.nix
    ./components.nix
    ./extensions.nix
  ];

  config = lib.mkIf cfg.enable {
    home = {
      packages = lib.optional (cfg.package != null) cfg.package;

      # Ensure directory structure exists
      file.".gemini/antigravity-cli/.keep".text = ''
        # Managed by Nix - programs.antigravity-cli module
      '';

      # This CLI accepts only a Gemini-format endpoint, so it can follow the
      # local proxy only because that proxy serves the Gemini generateContent
      # route natively (`/v1beta/models/<model>:generateContent` and its
      # streaming twin) alongside the OpenAI-compatible one. The root URL is
      # what goes here — the CLI appends the `/v1beta/...` path itself.
      sessionVariables = lib.mkIf config.programs.litellmLocal.enable {
        GOOGLE_GEMINI_BASE_URL = config.programs.litellmLocal.rootUrl;
      };
    };

    programs.antigravity-cli = {
      # `agy` came from the antigravity-cli Homebrew cask, which has no Linux
      # path. llm-agents.nix packages it for aarch64-darwin and x86_64-linux
      # alike; nixpkgs does not carry it at all.
      package = lib.mkDefault agyPackage;

      # Deliberately left unset. Selecting the router role here (`"subagent"`)
      # was tried and is now known to be rejected: the CLI validates `model`
      # against its own registry when it LOADS the settings file, and on a
      # miss discards the whole file — not just the model key — falling back
      # to built-in defaults. Sandbox, folder trust, permissions, policyPaths
      # and every configured MCP server silently stop applying:
      #
      #   failed to load cli settings, using defaults: invalid settings:
      #   model: invalid value { "name": "subagent" }
      #
      # This is schema validation, not routing, so no proxy alias or catch-all
      # route can satisfy it — the file is rejected before any request is made.
      # With the key absent the CLI picks its own default and still routes
      # through the proxy via GOOGLE_GEMINI_BASE_URL above, which is the
      # behaviour this module wants anyway. A consumer that needs a specific
      # model sets a value the CLI's own registry accepts (see the in-CLI
      # /model dialog), never a router role name.
    };
  };
}
