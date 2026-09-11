#!/usr/bin/env bash
# Compare the ai-stack registry's roles against what each endpoint serves.
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
# TWO THINGS ARE CHECKED, because a caller can address a role either way and
# only one of them was ever verified:
#
#   1. the role's MODEL ID resolves at either endpoint, and
#   2. the ROLE NAME ITSELF is addressable AT THE ROUTER.
#
# Checking only (1) is a false green, measured 2026-09-09: every role passed (1)
# at both endpoints while seven of eight failed (2), returning
# `400 no healthy deployments` to a real request. The registry calls role names
# "stable and consumer-facing" and the delegation skills instruct every agent to
# prefer a role alias over a physical id — so (2) is the condition real callers
# depend on, and it was the unchecked one.
#
# (2) IS DELIBERATELY NOT CHECKED LOCALLY, for two independent reasons:
#
#   * llama-swap's aliases are GENERATED from this same role map, so a local
#     role name cannot drift from it by construction. Checking it would compare
#     the role map against itself and prove nothing.
#   * llama-swap's /v1/models lists only physical ids and never its aliases, so
#     that source cannot answer the question anyway. Reading absence there as
#     "unroutable" reports all eight roles broken on a host serving them
#     perfectly — a false alarm this check briefly had.
#
# The router is the only endpoint keeping its own hand-maintained routing table,
# which makes it the only place the two can disagree.
#
# The router's /v1/model/info is a VALIDATED proxy for addressability, not an
# assumption: on 2026-09-09 it listed exactly one of the eight role names, and a
# real chat/completions request for each of the other seven returned 400. The
# cheap source and the expensive one agreed, so this reads the cheap one.
#
# Exit 1 on ANY drift, including a role that resolves at one endpoint but not
# the other. That asymmetric case is real breakage for half the callers, and a
# check that exited 0 on it would sit green in a timer while every routed
# delegation 404'd — which is exactly the silence this whole effort exists to
# end. It stays red until the registry or the router's table is corrected,
# which is the point.
#
# Exit 2 means the check could not run (no registry, or no endpoint answered).
# "Could not check" is never reported as "no drift": a run that reached nothing
# has verified nothing, and printing an all-clear for it is the same class of
# false green as (1) above.
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


def served(path, kind):
    """Every name this endpoint will answer to.

    Both endpoints publish aliases and physical ids in the same namespace, and
    that is deliberate: the question asked here is only ever "does this name
    resolve", so a name is a name. llama-swap lists its generated aliases as
    ids in /v1/models; the router lists each route's addressable `model_name`.
    """
    try:
        d = json.load(open(path))
    except Exception:
        return set()
    out = set()
    for row in d.get("data", []):
        if kind == "models":
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


local_names = served(sys.argv[1], "models") if local_ok else set()
router_names = served(sys.argv[2], "info") if router_ok else set()

print("endpoints: local=%s  router=%s" % (
    "reachable" if local_ok else "UNREACHABLE",
    "reachable" if router_ok else "UNREACHABLE"))
print()

if not (local_ok or router_ok):
    # Nothing was compared. Saying "no drift" here would be an all-clear for a
    # run that read no endpoint at all.
    print("VERIFIED NOTHING: no endpoint answered, so no role was checked.")
    raise SystemExit(2)


def mark(present, endpoint_ok):
    """`--` means absent; `?` means we could not look. Never conflate them."""
    if not endpoint_ok:
        return "?"
    return "yes" if present else "--"


roles = reg.get("models", {})
dead, split, unrouted = [], [], []

print("%-16s %-46s %-13s %s" % ("role", "model", "model[loc/rtr]", "name@rtr"))
for role, model in sorted(roles.items()):
    ml = mark(model in local_names, local_ok)
    mr = mark(model in router_names, router_ok)
    # Role-name addressability is a router-only question — see the header for
    # why the local endpoint is exempt rather than merely unchecked.
    nr = mark(role in router_names, router_ok)
    print("%-16s %-46s %-13s %s" % (role, model, "%s/%s" % (ml, mr), nr))

    if ml == "--" and mr == "--":
        dead.append((role, model))
    elif "--" in (ml, mr):
        split.append((role, model, ml, mr))
    # A role name the router cannot address breaks every caller that followed
    # the instruction to address the role rather than the model. Tracked
    # separately from a model-id mismatch because the fix is in the router's
    # routing table, not in the registry's ids.
    if nr == "--":
        unrouted.append(role)

print()
if split:
    print("MODEL RESOLVES AT ONLY ONE ENDPOINT — a caller using the other gets a 404:")
    for role, model, ml, mr in split:
        print("  %-16s %s (missing from %s)" % (role, model, "router" if mr == "--" else "local"))
    print("  These roles all follow services.aiStack.defaultLocalModelId, which")
    print("  resolves through the nix-ai MLX catalog. Change the catalog entry the")
    print("  consuming host selects (nix-darwin), not vars/ai-stack.nix — every role")
    print("  there is null by design and is populated at evaluation time.")
    print()
if dead:
    print("MODEL RESOLVES NOWHERE:")
    for role, model in dead:
        print("  %-16s %s" % (role, model))
    print()
if unrouted:
    print("ROLE NAME NOT ADDRESSABLE AT THE ROUTER — an agent addressing the role,")
    print("as the delegation skills instruct it to, gets 400 no healthy deployments")
    print("even though the underlying model is served:")
    for role in unrouted:
        print("  %s" % role)
    print("  Add a route whose model_name is the role name. llama-swap generates")
    print("  its aliases from this same role map, so it already resolves them; the")
    print("  router keeps its own table, which is the one that drifts.")
    print()

if dead or split or unrouted:
    raise SystemExit(1)
print("no drift: every role resolves, by id and by name, at every reachable endpoint")
PY
