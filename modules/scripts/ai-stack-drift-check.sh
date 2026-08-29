#!/usr/bin/env bash
# Compare the ai-stack registry's model ids against what each endpoint serves.
#
# WHY THIS EXISTS: the registry is generated from vars/ai-stack.nix at eval time
# and installed on every activation, so it is never a stale FILE — but the ids
# inside it are hand-written, and nothing has ever compared them to reality.
# `~/.agents/skills/delegate-to-ai` tells every agent to trust this file and
# never hardcode a physical model id, so a wrong id here misroutes every
# delegated call.
#
# Note the ids are NOT written in vars/ai-stack.nix — every role there is null,
# populated at evaluation time from services.aiStack.defaultLocalModelId, which
# the consuming host resolves through the MLX catalog. So the value being
# checked here crosses a repo boundary, which is exactly why no single repo's
# CI could have caught it.
#
# WHAT DRIFT ACTUALLY LOOKS LIKE, measured 2026-08-28: seven of eight capability
# roles named a model that llama-swap serves locally but the router does not.
# Nothing was "broken" — a local caller worked fine — while every router-routed
# caller got a 404 for the same role. That asymmetry is why this reports per
# endpoint instead of a single pass/fail.
#
# Exit 1 on ANY drift, including a model that resolves at one endpoint but not
# the other. That asymmetric case is real breakage for half the callers, and a
# check that exited 0 on it would sit green in a timer while every routed
# delegation 404'd — which is exactly the silence this whole effort exists to
# end. It stays red until vars/ai-stack.nix is corrected, which is the point.
set -euo pipefail

REGISTRY="${AI_STACK_REGISTRY:-$HOME/.config/ai-stack/registry.json}"
[ -f "$REGISTRY" ] || { echo "registry not found: $REGISTRY" >&2; exit 2; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

fetch() { curl -sS --max-time 45 --retry 2 --retry-delay 5 --retry-all-errors "$@"; }

local_ep=$(python3 -c 'import json,sys,os;print(json.load(open(sys.argv[1]))["endpoints"].get("mlx_local",""))' "$REGISTRY")
router_ep=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["endpoints"].get("router",""))' "$REGISTRY")

# An endpoint that cannot be reached is recorded as unknown, never as empty.
# Treating "unreachable" as "serves nothing" would report every model as drifted
# the moment a host was down — an alarm that cries wolf gets muted, and a muted
# drift check is worse than none.
if [ -n "$local_ep" ] && fetch "$local_ep/models" > "$work/local.json" 2>/dev/null; then
  local_ok=1
else
  local_ok=0
fi

router_base="${router_ep%/v1}"
if [ -n "$router_ep" ] && [ -n "${LLM_ROUTER_TOKEN_FILE:-}" ] && [ -f "${LLM_ROUTER_TOKEN_FILE}" ] \
  && fetch -H "Authorization: Bearer $(cat "$LLM_ROUTER_TOKEN_FILE")" \
     "$router_base/v1/model/info" > "$work/router.json" 2>/dev/null; then
  router_ok=1
else
  router_ok=0
fi

REGISTRY="$REGISTRY" LOCAL_OK="$local_ok" ROUTER_OK="$router_ok" \
python3 - "$work/local.json" "$work/router.json" <<'PY'
import json, os, sys

reg = json.load(open(os.environ["REGISTRY"]))
local_ok = os.environ["LOCAL_OK"] == "1"
router_ok = os.environ["ROUTER_OK"] == "1"

def ids(path, key):
    try:
        d = json.load(open(path))
    except Exception:
        return set()
    out = set()
    for row in d.get("data", []):
        if key == "models":
            out.add(row.get("id"))
        else:
            out.add(row.get("model_name"))
            up = (row.get("litellm_params") or {}).get("model") or ""
            # The router exposes the same model under a bare id and a
            # provider-prefixed alias; both count as resolvable.
            for pref in ("openai/", "openrouter/"):
                if up.startswith(pref):
                    out.add(up[len(pref):])
    return {i for i in out if i}

local_ids = ids(sys.argv[1], "models") if local_ok else set()
router_ids = ids(sys.argv[2], "info") if router_ok else set()

print("endpoints: local=%s  router=%s" % (
    "reachable" if local_ok else "UNREACHABLE",
    "reachable" if router_ok else "UNREACHABLE"))
print()

dead, split = [], []
for role, model in sorted(reg.get("models", {}).items()):
    l = "yes" if model in local_ids else ("--" if local_ok else "?")
    r = "yes" if model in router_ids else ("--" if router_ok else "?")
    print("%-16s %-52s local=%-4s router=%s" % (role, model, l, r))
    if l == "--" and r == "--":
        dead.append((role, model))
    elif "--" in (l, r):
        split.append((role, model, l, r))

print()
if split:
    print("RESOLVES AT ONLY ONE ENDPOINT — a caller using the other gets a 404:")
    for role, model, l, r in split:
        print("  %-16s %s (missing from %s)" % (role, model, "router" if r == "--" else "local"))
    print("  These roles all follow services.aiStack.defaultLocalModelId, which")
    print("  resolves through the nix-ai MLX catalog. Change the catalog entry the")
    print("  consuming host selects (nix-darwin), not vars/ai-stack.nix — every role")
    print("  there is null by design and is populated at evaluation time.")
    print()
if dead:
    print("RESOLVES NOWHERE:")
    for role, model in dead:
        print("  %-16s %s" % (role, model))
if dead or split:
    raise SystemExit(1)
print("no drift: every role resolves at every reachable endpoint")
PY
