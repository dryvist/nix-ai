# herdr

[herdr](https://github.com/herdrdev/herdr) is a background server that owns the
terminals coding agents run in: sessions survive a reboot, panes are marked
working/blocked/idle, and agents drive it themselves through a CLI and a
Unix-socket JSON API.

Two halves, one flake:

| Output | File | Runs |
| --- | --- | --- |
| `homeManagerModules.herdr` | `default.nix`, `options.nix`, `settings.nix` | the workstation |
| `nixosModules.herdr` | `nixos.nix` | the Linux guest, as a systemd service |

Both take their binary from the same `llm-agents` input, so a pane on the
server runs the same build as a pane on the Mac.

## Where CLI binaries come from

**nixpkgs → llm-agents.nix → homebrew (GUI only) → bunx → uvx.**

Claude Code, Codex, Antigravity CLI (`agy`) and qwen-code used to come from
**Homebrew casks and brews**. A cask has no Linux path, so a host evaluating
this flake on `x86_64-linux` got config files and no binaries — concretely why
the stack could not leave the MacBook.

| CLI | Source |
| --- | --- |
| Claude Code, `agy`, Copilot CLI, herdr | `llm-agents.nix` |
| Codex, OpenCode, qwen-code, Cursor | nixpkgs 26.05 |
| Claude Desktop, Codex app, ChatGPT, Antigravity, Antigravity IDE | homebrew |

[`numtide/llm-agents.nix`](https://github.com/numtide/llm-agents.nix) carries
150+ agent CLIs for `x86_64-linux`, `aarch64-linux` and `aarch64-darwin` — an
exact match for this flake's `supportedSystems` — rebuilt daily and substituted
from `cache.numtide.com`.

Two rules that will bite otherwise:

- **It deliberately does not `follows` nixpkgs**, unlike every other input.
  It pins its own `nixpkgs-unstable` and the numtide cache is keyed to that
  pin; forcing 26.05 breaks builds *and* loses every cache hit.
- **`lib/homebrew.nix` is GUI-only.** Do not add a CLI cask back.

### Known cost: macOS TCC

`modules/codex/default.nix` used to note that Codex was a cask specifically for
*stable TCC paths*. A Nix store path changes on every version bump, so macOS
may re-prompt for permissions after an upgrade. That is the accepted tradeoff
for having a Linux path at all. If it proves disruptive, fix it for darwin
specifically rather than reverting the Linux path.

## Two conflicts with declarative config

Both are things herdr's own quick-start walks straight into.

**Do not run `herdr integration install <agent>`.** It writes lifecycle hooks
into each agent's own config. For Claude Code that means editing
`~/.claude/settings.json`, which `nix-claude-code` renders read-only from the
Nix store — the write fails, or the next `switch` reverts it. Express those
hooks as `programs.claude.hooks` in `modules/claude-config.nix` instead.

**herdr fetches agent-manifest updates from `herdr.dev` at runtime** and applies
them without a restart: undeclared mutable state reaching the internet on an
otherwise declarative guest. Local manifests take precedence, so declare the
ones that matter in `programs.herdr.agentManifests` rather than trusting
whatever the network last handed the daemon, and set the guest's egress policy
deliberately.

## Agent detection

herdr classifies a pane by matching manifest rules against the foreground
process. A CLI with no manifest shows as a bare shell, and everything
downstream — the Slack bridge's blocked-agent alerts, `herdr agent wait`, the
dashboard's approvals — silently sees nothing to report.

`lib/checks/herdr.nix` fails when an enabled CLI is neither detected upstream,
nor given a manifest here, nor named in `knownUnsupportedAgents`.

`qwen-code` and `cecli` are in that list today: herdr ships no manifest for
either, and the rule schema is herdr's, so those entries are **declared rather
than guessed at**. Author real ones against
`herdr agent explain <target> --json` on a live pane, then reload with
`herdr server reload-agent-manifests`.

## The socket path is a contract

`nixos.nix` sets `RuntimeDirectory=herdr`, pinning the control socket at
`/run/herdr` instead of a uid-derived `$XDG_RUNTIME_DIR` path. That is
deliberate: the Slack bridge runs in its own container and forwards the socket
over SSH, which needs a predictable path. Changing it breaks that forward, and
the failure mode is a permanently quiet fleet rather than an error.
