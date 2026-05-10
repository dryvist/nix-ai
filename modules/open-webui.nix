{
  config,
  lib,
  pkgs,
  ...
}:
#
# Open WebUI Configuration Module
#
# Manages the Open WebUI service for interacting with MLX and other
# OpenAI-compatible backends via a web browser.
#
# NOTE: open-webui is installed via `uv tool install` (not nixpkgs) because:
#   - stable nixpkgs: open-webui → pgvector → postgresql-test-hook (badPlatforms = darwin)
#   - unstable nixpkgs: open-webui has unfree license blocked by default allowUnfree
#   The uv-installed binary lands at ~/.local/bin/open-webui
#
# Web UI: http://localhost:8080
# Backend: http://127.0.0.1:11434/v1 (MLX vllm-mlx, OpenAI-compatible)
#
{
  config = lib.mkIf pkgs.stdenv.isDarwin {
    # ============================================================================
    # LaunchAgent (Manual Start)
    # ============================================================================
    # Does not auto-start at login. Start on demand:
    #   launchctl kickstart -k gui/$(id -u)/app.open-webui
    # Stop:
    #   launchctl kill TERM gui/$(id -u)/app.open-webui
    #
    # WorkingDirectory is required: open-webui writes .webui_secret_key to
    # Path.cwd() at startup; without it launchd defaults cwd to / (read-only
    # SSV) and the process crashes immediately on every spawn.
    launchd.agents.open-webui = {
      enable = true;
      config = {
        Label = "app.open-webui";
        ProgramArguments = [
          "${config.home.homeDirectory}/.local/bin/open-webui"
          "serve"
        ];
        EnvironmentVariables = {
          OPENAI_API_BASE_URL = "http://127.0.0.1:11434/v1";
          OPENAI_API_KEY = "not-needed";
        };
        WorkingDirectory = "${config.home.homeDirectory}/.open-webui";
        RunAtLoad = false;
        KeepAlive = false;
        ThrottleInterval = 60;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/OpenWebUI/open-webui.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/OpenWebUI/open-webui.error.log";
      };
    };

    home.activation.createOpenWebUIDataDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.open-webui" "$HOME/Library/Logs/OpenWebUI"
    '';
    # ============================================================================
    # Notes
    # ============================================================================
    # - Web UI accessible at http://localhost:8080
    # - Connects to MLX vllm-mlx at http://127.0.0.1:11434/v1 (OpenAI-compatible)
    # - Data stored at ~/.open-webui/ (created by activation if absent)
    # - Logs: ~/Library/Logs/OpenWebUI/open-webui.log
    # - Installed via `uv tool install open-webui --python 3.14` in home.activation
    # - Binary at ~/.local/bin/open-webui (uv tool bin directory)
  };
}
