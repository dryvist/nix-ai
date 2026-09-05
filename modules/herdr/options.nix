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
        `agent-detection/` manifest overrides. Upstream default.

        Changing it does not relocate herdr on its own. `HERDR_SOCKET_PATH` is
        the only variable that moves the control socket; `launchd.nix` derives
        the server's from this value, and an interactive client needs the same
        variable to follow a non-default directory.
      '';
    };

    settings = lib.mkOption {
      inherit (tomlFormat) type;
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

    integrations = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "claude"
          "codex"
          "opencode"
        ]
      );
      default = [ ];
      example = [
        "claude"
        "codex"
      ];
      description = ''
        Agent CLIs whose herdr lifecycle hooks are declared. Each hook lets the
        agent report its own session id and working/blocked/idle transitions;
        without one herdr falls back to terminal heuristics.

        Payloads are referenced from the package's own
        `share/herdr/integrations/`, so they track the pinned herdr version.
        Never run `herdr integration install` — it writes into config
        directories home-manager renders read-only.
      '';
    };

    agentManifests = lib.mkOption {
      type = lib.types.attrsOf tomlFormat.type;
      default = { };
      example = lib.literalExpression ''
        {
          qwen = {
            id = "qwen";
            version = "2099.01.01.1";
            min_engine_version = 1;
            rules = [
              {
                id = "composer_idle";
                state = "idle";
                region = "bottom_non_empty_lines(5)";
              }
            ];
          };
        }
      '';
      description = ''
        Local agent-detection manifest overrides, rendered to
        `<configDir>/agent-detection/<name>.toml`. Local manifests take
        precedence over herdr's bundled and remotely-fetched ones.

        `<name>` must be HERDR's name for the agent, not this flake's option
        name — herdr selects a manifest by filename, so `qwen-code.toml` is
        ignored where `qwen.toml` is honoured, and the mismatch is silent. Note
        this is the opposite of `knownUpstreamAgents`, which is keyed by option
        name.

        Any CLI this flake enables that herdr does not already detect needs an
        entry here, or herdr shows its pane as a bare shell with no
        working/blocked/idle state. `lib/checks/herdr.nix` enforces that.
        `herdr server agent-manifests` lists what herdr currently ships; that
        set changes upstream, so it is not enumerated here.

        The rule schema is herdr's, not ours — author an entry against
        `herdr agent explain <target> --json` on a live pane rather than from
        memory, and reload with `herdr server reload-agent-manifests`.
      '';
    };

    knownUnsupportedAgents = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cecli"
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
        # herdr's manifest is named `qwen`; this flake's option is `qwen-code`,
        # the same name skew `antigravity-cli` (herdr: `agy`) already carries.
        # Verified live: `herdr agent explain` on a qwen pane reports
        # manifest qwen.toml 2026.08.14.1, matched rule `composer_idle`,
        # no fallback and no warning.
        "qwen-code"
      ];
      description = ''
        Agents herdr detects out of the box, as declared by its own supported-
        agents documentation. Read-only: it describes upstream, so a consumer
        overriding it would only be lying to the coverage check.

        Names here are THIS flake's option names, not herdr's manifest names,
        because the coverage check keys off the option that enables the CLI.
        `agentManifests` is the other way round — it is keyed by herdr's name,
        because there the name becomes a filename herdr has to match.
      '';
    };
  };
}
