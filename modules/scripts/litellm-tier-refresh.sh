#!/usr/bin/env bash
# Re-rank the local proxy's fallback tier against the live OpenRouter catalog.
#
# WHY THIS IS GENERATED AND NOT HAND-WRITTEN: the catalog moves daily. The
# first hand-written version of this tier recorded deepseek-v4-flash at
# $0.030/$0.100 with a 1,310,720-token window; one day later the catalog said
# $0.087/$0.173 and 1,048,576. A price table maintained by hand is wrong
# almost immediately, and a chain ordered by wrong prices is not cost-ordered.
#
# TWO SOURCES, INTERSECTED, and the intersection is the whole point. The
# OpenRouter catalog says what a model COSTS and what it can do; the upstream
# router says what this estate can actually REACH. Ranking the catalog alone
# proposes models the router refuses with `no router` — measured, not guessed:
# every one of the three cheapest eligible catalog models 404'd through the
# proxy because the router serves an explicit allowlist, not the whole catalog.
#
# The catalog is keyless. The router needs its bearer, which is why this runs
# on a host that has one rather than in CI — a CI-built ranking could not tell
# a servable model from an unreachable one, which is the error this exists to
# prevent.
#
# THIS SCRIPT ONLY PROPOSES. It rewrites the `members` array in the candidates
# file and nothing else; the `policy` block is hand-owned and preserved
# verbatim. Selection is by catalog metadata, which says what a model claims,
# never what it does — `litellm-fallback-probe` is what proves a member
# actually answers, and that check is the merge gate, not this script.
set -euo pipefail

CANDIDATES="${1:-}"
if [ -z "$CANDIDATES" ]; then
  echo "usage: ${0##*/} PATH_TO_tier-candidates.json" >&2
  exit 2
fi
[ -f "$CANDIDATES" ] || { echo "no such file: $CANDIDATES" >&2; exit 2; }

CATALOG_URL="${OPENROUTER_CATALOG_URL:-https://openrouter.ai/api/v1/models}"

ROUTER_URL="${LLM_ROUTER_URL:?LLM_ROUTER_URL must be set}"
ROUTER_TOKEN_FILE="${LLM_ROUTER_TOKEN_FILE:?LLM_ROUTER_TOKEN_FILE must be set}"
# LLM_ROUTER_URL already ends in /v1; model/info hangs off the same /v1, so
# strip before appending or the request becomes /v1/v1/... and returns nothing.
ROUTER_BASE="${ROUTER_URL%/v1}"

# Via files, not environment: the catalog is megabytes, and an env var that
# large exceeds the exec argument limit (E2BIG) on macOS.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -sS --max-time 60 "$CATALOG_URL" > "$work/catalog.json"
curl -sS --max-time 60 -H "Authorization: Bearer $(cat "$ROUTER_TOKEN_FILE")" \
  "$ROUTER_BASE/v1/model/info" > "$work/served.json"

python3 - "$CANDIDATES" "$work/catalog.json" "$work/served.json" <<'PY'
import json, os, sys, datetime

path = sys.argv[1]
doc = json.load(open(path))
policy = doc["policy"]
catalog = json.load(open(sys.argv[2]))["data"]

# What the router will actually serve. Each entry's litellm_params.model is the
# upstream id (`openrouter/<catalog id>`); model_name is the name to REQUEST.
# Both are needed: selection is judged on catalog metadata keyed by the
# upstream id, but the chain must name what the router answers to.
served_rows = json.load(open(sys.argv[3])).get("data", [])
request_name = {}
for row in served_rows:
    upstream = (row.get("litellm_params") or {}).get("model") or ""
    if upstream.startswith("openrouter/"):
        # Prefer the shortest name that resolves: the router exposes many
        # models under both a bare id and an `openrouter/`-prefixed alias.
        cid = upstream[len("openrouter/"):]
        name = row.get("model_name")
        if cid not in request_name or len(name) < len(request_name[cid]):
            request_name[cid] = name

need_ctx = policy["requiredInputTokens"]
deny = set(policy.get("deny", []))
pin = policy.get("pin", [])
count = policy["memberCount"]
# Free models share ONE upstream quota pool, so a chain made only of them has a
# single point of failure wearing three names: exhaust the daily free cap and
# every rung dies in the same instant. The tail is reserved for models that
# bill, which do not share that cap.
paid_tail = policy.get("paidTail", 0)

def price(m, key):
    # A missing or negative price means "not a fixed per-token price" — the
    # meta-routers (openrouter/auto, openrouter/fusion) publish -1. Sorting
    # those as cheapest would put a model of unknown cost and unknown identity
    # at the head of the chain, which is the opposite of the point.
    try:
        v = float(m.get("pricing", {}).get(key))
    except (TypeError, ValueError):
        return None
    return None if v < 0 else v

def eligible(m):
    if m["id"] in deny:
        return False
    # Unreachable is not a ranking penalty, it is disqualifying.
    if m["id"] not in request_name:
        return False
    if (m.get("context_length") or 0) < need_ctx:
        return False
    p, c = price(m, "prompt"), price(m, "completion")
    if p is None or c is None:
        return False
    arch = m.get("architecture") or {}
    # Text out only: a zero-cost audio or image model sorts to the very top on
    # price and cannot serve a single subagent turn.
    if arch.get("output_modalities") != ["text"]:
        return False
    # Tool calling is not optional. A subagent that cannot call tools fails on
    # its first action, and it fails as a wrong answer rather than an error —
    # the worst shape of failure and the hardest to notice.
    if "tools" not in (m.get("supported_parameters") or []):
        return False
    return True

by_id = {m["id"]: m for m in catalog}
pool = [m for m in catalog if eligible(m)]
# Cheapest first, tie-broken by the larger window. Both halves of the price
# matter: a model with free input and expensive output is not cheap.
pool.sort(key=lambda m: (price(m, "prompt") + price(m, "completion"),
                         -(m.get("context_length") or 0)))

def is_free(m):
    return price(m, "prompt") == 0 and price(m, "completion") == 0

chosen, seen = [], set()
missing = []
for pid in pin:                      # hand-pinned entries lead, in given order
    m = by_id.get(pid)
    if m is not None and pid not in request_name:
        m = None
    if m is None:
        missing.append(pid)
        continue
    chosen.append(m); seen.add(pid)
free_slots = count - paid_tail
for m in pool:
    if len(chosen) >= free_slots:
        break
    if m["id"] not in seen:
        chosen.append(m); seen.add(m["id"])

# Cheapest BILLING models for the tail, in the same cost order.
for m in (x for x in pool if not is_free(x)):
    if len(chosen) >= count:
        break
    if m["id"] not in seen:
        chosen.append(m); seen.add(m["id"])

if paid_tail and not any(not is_free(m) for m in chosen):
    sys.exit("policy requires a paid tail but no billing model is eligible; "
             "a free-only chain dies all at once when the shared quota is spent")

if missing:
    # A pin that has left the catalog is a hand-made decision that has expired.
    # Silently dropping it would quietly discard an operator's override.
    print("WARNING: pinned model(s) absent from catalog: %s" % ", ".join(missing),
          file=sys.stderr)

if len(chosen) < 2:
    sys.exit("only %d eligible model(s); a chain needs at least 2" % len(chosen))

# The head of the chain is ALWAYS named `subagent`, whatever model wins the
# ranking. Consumers name that one string forever; a refresh reorders what sits
# behind it without touching a single consumer. Naming the head after its
# current model is what makes a catalog change into a config change.
#
# It also shadows the upstream router's own `subagent` alias, which still
# points at a retired model: an explicit model_list group always beats the `*`
# wildcard, so defining it here fixes the dead alias for this host.
def name(i):
    return "subagent" if i == 0 else "subagent-fallback%d" % i

doc["generatedAt"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
doc["members"] = [{
    "name": name(i),
    "upstream": request_name[m["id"]],
    "catalogId": m["id"],
    "contextLength": m.get("context_length"),
    # Three decimals, not the full float: published prices drift in the fourth
    # decimal between consecutive fetches minutes apart (deepseek-v4-flash was
    # seen at 0.0865 and 0.0862 in one session). At full precision every run
    # produces a diff that means nothing, which trains a reader to skim the one
    # that does. Three decimals still separates every tier in the pool.
    "promptCostPerMtok": round(price(m, "prompt") * 1e6, 3),
    "completionCostPerMtok": round(price(m, "completion") * 1e6, 3),
} for i, m in enumerate(chosen)]

with open(path, "w") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")

for m in doc["members"]:
    print("%-16s %-46s ctx=%-9s $%s/$%s" % (
        m["name"], m["upstream"], m["contextLength"],
        m["promptCostPerMtok"], m["completionCostPerMtok"]))
print("\n%d of %d catalog models are both eligible and router-served; wrote %s"
      % (len(pool), len(catalog), path))
PY
