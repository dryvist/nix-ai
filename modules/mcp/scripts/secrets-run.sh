#!/usr/bin/env bash
# secrets-run - OpenBao-first, Doppler-fallback launch for an MCP server.
#
# Picks its path at RUNTIME, not at Nix eval time, so one definition serves
# every account: an account with an OpenBao AppRole secret-zero file (e.g.
# open-llm, which has no Doppler token by design) uses openbao-run; an
# account without that file (e.g. claude) falls back to `doppler run`
# exactly as before. Same env-file / KV-path convention as nix-darwin's
# zcode launcher ($HOME/.openbao/<domain>.env, secret/apps/<domain>).
#
# Usage: secrets-run <domain> -- <command> [args...]
domain="${1:?secrets-run: missing <domain>}"
shift
env_file="$HOME/.openbao/${domain}.env"
if [ -f "$env_file" ]; then
  exec openbao-run --domain "$domain" --env-file "$env_file" --secrets "apps/${domain}" -- "$@"
else
  exec doppler run -p "$DOPPLER_PROJECT" -c "$DOPPLER_CONFIG" -- "$@"
fi
