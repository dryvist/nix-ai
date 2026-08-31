# herdr operations: enable, verify detection, author a manifest

> Detection state is mostly fetched from the network, not pinned by this flake.
> Read [`docs/architecture/herdr.md`](../architecture/herdr.md) before changing
> anything about manifests — it explains the precedence that decides which
> rules are actually live.

herdr is enabled by default in `modules/default.nix`, so a consumer normally
needs no config at all. A workstation with no `herdr` binary is usually running
a stale pin of this flake rather than a disabled module — but check
`programs.herdr.enable` and `programs.herdr.package` first, since a consumer can
set either to disable installation deliberately. Confirm which before bumping a
pin that is not the problem.

## Verify it is actually running

1. `herdr --version` — confirms the binary is on PATH from the current
   generation. If it is missing, check `enable` and `package` before assuming a
   stale pin.
2. `herdr status` — reports client and server separately. The workstation half
   starts no daemon of its own, so `server: not running` is normal until a
   client or `herdr server` starts one. On a guest, the systemd unit owns it.
3. `herdr session list` — a running session and its socket path.

## Verify detection on a live pane

Do this on a real pane. Detection reads what the terminal renders, so it cannot
be checked from the schema or from memory.

1. Create a workspace, which also creates its root pane:
   `herdr workspace create --cwd <repo> --label <name> --focus`
2. Start the agent in that pane, which must be at an interactive shell prompt:
   `herdr agent start <name> --kind <kind> --pane <id>`
   A successful start already reports `agent`, `agent_status` and
   `interactive_ready`.
3. `herdr agent explain <name> --json` — the authoritative answer. Read
   `state`, `matched_rule`, and `manifest_source`. `manifest_source` tells you
   whether a local override or a fetched manifest decided the outcome.

## Author a manifest for an undetected agent

Only for a CLI herdr does not already know. Check first: a manifest may already
exist under a different name — herdr's names are its own, not this flake's
option names.

1. `herdr server agent-manifests` — lists every active manifest and where it
   came from. If the agent appears here, no authoring is needed.
2. Start the agent in a pane and capture real output with
   `herdr agent explain <name> --json`. Author rules against that, never from
   the rule schema alone.
3. Declare it in `programs.herdr.agentManifests.<name>`, which renders to
   `<configDir>/agent-detection/<name>.toml` and takes precedence over both the
   fetched and bundled copies.
4. `herdr server reload-agent-manifests`, then re-run `explain` and confirm
   `local_override_shadowing_remote` is now true.
5. Remove the name from `knownUnsupportedAgents` only after step 4 passes.

## Diagnose a pane stuck as a bare shell

A pane with no detected agent still works — it is just reported as a plain
shell, so nothing downstream fires on its state. Work down this list:

1. `herdr agent list` — if the agent is absent, the pane never had one started,
   or the process exited.
2. `herdr agent explain <name> --json` and read `fallback_reason` and
   `warning`. A populated `fallback_reason` means rules were evaluated and none
   matched, which is a manifest problem.
3. `herdr server agent-manifests` — confirm a manifest for that agent is active
   at all, and check whether a fetched copy was ignored for being older than
   the bundled one.
4. If the agent is genuinely unsupported, add it to `knownUnsupportedAgents` so
   the gap is declared, and the coverage check stops failing.

## Two traps that cost real time

**A standalone `agent wait` for `idle` right after `agent prompt` can match the
state the agent never left.** Use `--wait` on the prompt itself rather than
sequencing two commands:

```bash
herdr agent prompt <name> "<text>" --wait --timeout 300000
```

`--wait` settles on the first `idle`, `done` or `blocked` after submission, and
a prompt that produces no lifecycle change within five seconds returns
`agent_prompt_stalled` rather than waiting forever. herdr's own guidance
(`herdr --skill`) is explicit that repeating those defaults with `--until` is
wrong. Reserve `--until` for a state-specific wait on an already-running agent,
such as `--until blocked` to catch an approval prompt.

Note there are five states, not three: `--until idle` alone can miss an agent
that settles on `done`.

**`config.toml` is a read-only symlink into the Nix store.** Any herdr
subcommand that rewrites its own config fails or is reverted on the next
switch. Express the change as `programs.herdr.settings` instead. This is the
same conflict class as `herdr integration install`, which
[`modules/herdr/README.md`](../../modules/herdr/README.md) covers.

## What survives a restart, and what does not

Stopping and restarting the server restores workspaces, panes and their working
directories from the persisted session. It does **not** resurrect the agent
processes that were running in those panes — they come back as plain shells at
the right directory. Plan reattachment around that: the layout survives, the
running agent does not.

## Related

- [`docs/architecture/herdr.md`](../architecture/herdr.md) — topology, socket
  ownership, and detection precedence.
- [`modules/herdr/README.md`](../../modules/herdr/README.md) — binary sources
  and the declarative-config conflicts.
