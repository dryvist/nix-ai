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

Only `cecli` is in that list. herdr ships no manifest for it, and the rule
schema is herdr's, so the entry is **declared rather than guessed at**. Author
a real one against `herdr agent explain <target> --json` on a live pane, then
reload with `herdr server reload-agent-manifests`.

`qwen-code` was listed too, and that was wrong. herdr detects it out of the box
via its `qwen` manifest — a live pane reports `manifest qwen.toml`
`2026.08.14.1`, matched rule `composer_idle`, no fallback and no warning. Names
skew between the two systems: herdr calls it `qwen`, this flake calls the option
`qwen-code`, the same skew `antigravity-cli` (herdr: `agy`) already carries.

## Detection state is fetched, not pinned

`herdr server agent-manifests` reports what is actually live. Measured on the
workstation: **19 of 20 manifests came from the network**, one (`grok`) fell
back to the bundled copy because the fetched version was older than the one
herdr shipped.

So the rules that decide working/blocked/idle are, by default, remote state
refreshed at runtime — which is why `agentManifests` exists. A local override
wins, and `explain` names the winner in `manifest_source` and flags it in
`local_override_shadowing_remote`.

## Unfree packages stay out of the defaults

`services.herdr.agentPackages` defaults to the agent CLIs this flake manages,
and every one of them is freely licensed, so enabling the service evaluates on
a stock host.

`cursor-cli` is deliberately excluded. It is unfree, and an unfree default made
`services.herdr.enable = true` fail at **evaluation** on any host that had not
opted in:

```text
error: Refusing to evaluate package 'cursor-cli-...' because it has an unfree license
```

The error names a package the operator never asked for, so it reads as
unrelated to the option they just set. Add it through `extraPackages`, together
with the host's own unfree opt-in.

## The socket path is a contract

`nixos.nix` pins the control socket at `/run/herdr/herdr.sock`, because the
Slack bridge runs in its own container and forwards it over SSH, which needs a
predictable path.

**`RuntimeDirectory` is not what pins it.** herdr derives its socket from the
**config** directory — on the workstation `herdr status` reports
`~/.config/herdr/herdr.sock`, and `XDG_RUNTIME_DIR` appears once in the 0.8.2
binary, in unrelated pane-graphics validation. The pin is `HERDR_SOCKET_PATH`,
set in the unit's `environment`; `RuntimeDirectory` only creates and tears down
the directory it lives in. Setting one without the other yields an empty
`/run/herdr` and a socket under the state directory.

Changing either breaks the forward, and the failure mode is a permanently quiet
fleet rather than an error.
