#
# herdr Module — Option Declarations
#
{ lib, pkgs, ... }:

let
  tomlFormat = pkgs.formats.toml { };
in
{
  options.programs.herdr = {
    enable = lib.mkEnableOption "herdr (terminal workspace manager for AI coding agents)";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        herdr package. Defaults to llm-agents.nix's herdr — nixpkgs carries it
        only on unstable, and this flake pins the 26.05 channel. Null skips
        installation, for a host that supplies the binary itself.
      '';
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = ".config/herdr";
      description = ''
        Directory (relative to $HOME) holding `config.toml` and the
        `agent-detection/` manifest overrides. Upstream default; changing it
        also requires HERDR_CONFIG_DIR in the environment.
      '';
    };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = { };
      example = lib.literalExpression ''
        {
          ui.sidebar = "left";
          worktrees.directory = "~/git/worktrees";
        }
      '';
      description = ''
        Contents of `config.toml`. Upstream sections are [terminal],
        [worktrees], [remote], [keys], [theme], [ui], [ui.sound],
        [experimental] and [session]. Free-form on purpose: herdr's config
        reference is the schema, and mirroring it here would go stale.
      '';
    };

    remotes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        herdr = "herdr.example.invalid";
      };
      description = ''
        Named SSH remotes, rendered into `[remote]`. `herdr --remote <name>`
        then starts or attaches to that host's herdr server and streams its UI
        back, which is how a workstation drives the server-hosted herd.
      '';
    };

    defaultRemote = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Name from `remotes` to use when `--remote` is given no argument.";
    };

    agentManifests = lib.mkOption {
      type = lib.types.attrsOf tomlFormat.type;
      default = { };
      example = lib.literalExpression ''
        { qwen-code = { detection = { }; }; }
      '';
      description = ''
        Local agent-detection manifest overrides, rendered to
        `<configDir>/agent-detection/<name>.toml`. Local manifests take
        precedence over herdr's bundled and remotely-fetched ones.

        herdr ships manifests for Claude Code, Codex, Cursor Agent, OpenCode,
        Copilot CLI, Antigravity CLI, Grok, Droid, Pi and Hermes Agent. Any CLI
        this flake enables that is NOT on that list needs an entry here, or
        herdr will show its pane as a bare shell with no working/blocked/idle
        state. `lib/checks/herdr.nix` enforces that.

        The rule schema is herdr's, not ours — author an entry against
        `herdr agent explain <target> --json` on a live pane rather than from
        memory, and reload with `herdr server reload-agent-manifests`.
      '';
    };

    knownUnsupportedAgents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cecli"
        "qwen-code"
      ];
      description = ''
        CLIs this flake enables that herdr knowingly cannot detect, and for
        which no local manifest has been authored yet. Their panes work — they
        are just reported as a plain shell, so nothing downstream fires on
        their state.

        This list exists so the gap is DECLARED rather than silent: the
        coverage check in lib/checks/herdr.nix fails for any enabled CLI that
        is neither detected upstream, nor given a manifest, nor listed here.
        Adding a name here is a deliberate, reviewable act; forgetting one is
        not possible.

        Shrink it by authoring manifests against `herdr agent explain` output.
      '';
    };

    knownUpstreamAgents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = [
        "antigravity-cli"
        "claude"
        "codex"
        "copilot"
        "cursor"
        "droid"
        "grok"
        "hermes"
        "opencode"
        "pi"
      ];
      description = ''
        Agents herdr detects out of the box, as declared by its own supported-
        agents documentation. Read-only: it describes upstream, so a consumer
        overriding it would only be lying to the coverage check.
      '';
    };
  };
}
