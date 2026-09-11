#!/usr/bin/env bash
# Behavioural tests for ai-stack-drift-check.
#
# The check compares the ai-stack registry's roles against what two endpoints
# serve. Four properties are fenced here, each one a bug this check either had
# or would have been useless without:
#
# (A) A ROLE NAME THE ROUTER CANNOT ADDRESS IS DRIFT. Every role can pass an
#     id-only comparison while the router has no route whose model_name is the
#     role name — measured 2026-09-09, seven of eight roles in exactly that
#     state, each returning `400 no healthy deployments` to a real request
#     while the check sat green. The registry calls role names stable and
#     consumer-facing and the delegation skills tell every agent to prefer a
#     role alias over a physical id, so this is the condition callers depend on.
#
# (B) THE LOCAL ENDPOINT MUST NOT BE BLAMED FOR NOT LISTING ALIASES. llama-swap
#     resolves its aliases but /v1/models enumerates only physical ids. An
#     earlier draft of this check read that absence as unroutable and reported
#     all eight roles broken on a host serving them perfectly. A false alarm
#     gets a checker muted, and a muted checker is worse than none.
#
# (C) "COULD NOT CHECK" IS NEVER "NO DRIFT". With no endpoint answering, a run
#     has verified nothing; printing an all-clear for it is the same false green
#     as (A). Exit 2 and say so.
#
# (D) ANTI-VACUITY. (A) must report EXACTLY the roles seeded as unroutable. A
#     checker that flags all of them, or none, is as useless as one that
#     crashes, and both would pass a test that only asserted a non-zero exit.
set -o errexit -o nounset -o pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$repo_root/modules/scripts/ai-stack-drift-check.sh"
[ -f "$CHECK" ] || { echo "FAIL missing script under test: $CHECK"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"; [ -n "${stub_pid:-}" ] && kill "$stub_pid" 2>/dev/null || true' EXIT

fail=0
check() {
  local label="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    echo "  ok   $label -> $got"
  else
    echo "  FAIL $label -> got '$got', want '$want'"
    fail=1
  fi
}

# The router path is bearer-gated; the script skips the router entirely when the
# token file is absent, which would make every router assertion below vacuous.
printf 'stub-token' > "$work/token"
export LLM_ROUTER_TOKEN_FILE="$work/token"

# ---- stub endpoint --------------------------------------------------------
# Serves both shapes the check reads: /v1/models the way llama-swap does (bare
# physical ids, no aliases) and /v1/model/info the way the router does
# (addressable model_name plus the provider-prefixed upstream). Response bodies
# are read from files per request so one stub covers every case below.
cat > "$work/stub.py" <<'PY'
import http.server, pathlib, socketserver, sys

root = pathlib.Path(sys.argv[1])


class Server(http.server.HTTPServer):
    # http.server's server_bind calls socket.getfqdn(), a reverse lookup that
    # took 35s on a workstation whose resolver has no answer for the loopback
    # address — the stub then bound long after the test gave up. Nothing here
    # reads server_name, so skip the lookup entirely.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = {"/v1/models": "models.json", "/v1/model/info": "info.json"}.get(self.path)
        payload = root / name if name else None
        if payload is None or not payload.exists():
            self.send_response(404)
            self.end_headers()
            return
        body = payload.read_bytes()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


srv = Server(("127.0.0.1", 0), H)
(root / "port").write_text(str(srv.server_port))
srv.serve_forever()
PY

python3 "$work/stub.py" "$work" >"$work/stub.log" 2>&1 &
stub_pid=$!
for _ in $(seq 1 50); do
  [ -s "$work/port" ] && break
  sleep 0.1
done
[ -s "$work/port" ] || { echo "FAIL stub never bound a port"; cat "$work/stub.log" >&2; exit 1; }
port="$(cat "$work/port")"

# Fixtures. THE_MODEL is served by both endpoints throughout, so every failure
# below is about names rather than about a missing model.
THE_MODEL="vendor/model-a"
OTHER_MODEL="vendor/model-b"

write_registry() {
  # $1 = path, $2.. = role names; every role points at THE_MODEL.
  local out="$1"; shift
  python3 - "$out" "$THE_MODEL" "$@" <<'PY'
import json, sys
out, model, *roles = sys.argv[1:]
json.dump({"models": {r: model for r in roles},
           "endpoints": {}}, open(out, "w"))
PY
}

set_endpoints() {
  # $1 = registry path, $2 = local url or empty, $3 = router url or empty
  python3 - "$@" <<'PY'
import json, sys
path, local, router = sys.argv[1:4]
d = json.load(open(path))
eps = {}
if local:
    eps["mlx_local"] = local
if router:
    eps["router"] = router
d["endpoints"] = eps
json.dump(d, open(path, "w"))
PY
}

# llama-swap shape: physical ids only, never aliases.
write_models() {
  python3 - "$work/models.json" "$@" <<'PY'
import json, sys
out, *ids = sys.argv[1:]
json.dump({"data": [{"id": i} for i in ids]}, open(out, "w"))
PY
}

# Router shape: each entry's model_name is what a caller may address.
write_info() {
  python3 - "$work/info.json" "$@" <<'PY'
import json, sys
out, *names = sys.argv[1:]
json.dump({"data": [{"model_name": n,
                     "litellm_params": {"model": "openai/" + n}} for n in names]},
          open(out, "w"))
PY
}

run_check() {
  # Echoes output, returns the exit status in $rc without tripping errexit.
  set +o errexit
  AI_STACK_REGISTRY="$1" bash "$CHECK" > "$work/out.txt" 2>"$work/err.txt"
  rc=$?
  set -o errexit
}

ROLES="coding default quickest small tool-calling"

# ---- (A) + (D) role names the router cannot address ----------------------
# Router addresses THE_MODEL and the role name `tool-calling`, but not the other
# four roles. Exactly those four must be reported.
echo "(A) router missing four of five role names"
write_registry "$work/reg-a.json" $ROLES
set_endpoints "$work/reg-a.json" "http://127.0.0.1:$port/v1" "http://127.0.0.1:$port/v1"
write_models "$THE_MODEL"
write_info "$THE_MODEL" "tool-calling"
run_check "$work/reg-a.json"
check "exit status" "1" "$rc"
check "reports the unroutable heading" "yes" \
  "$(grep -q 'ROLE NAME NOT ADDRESSABLE AT THE ROUTER' "$work/out.txt" && echo yes || echo no)"

# The reported set must be exactly the four seeded roles. Parsed from the
# indented list under the heading, so a checker that flagged all five or none
# fails here rather than sliding by on a non-zero exit.
# `|| true` is load-bearing: with no heading present grep matches nothing and
# exits 1, which under errexit aborts the whole run inside a command
# substitution — so a regression would kill the test mid-way instead of
# reporting every failed assertion. Verified against the pre-fix script, where
# this line ended the run after two failures.
reported="$( { sed -n '/ROLE NAME NOT ADDRESSABLE AT THE ROUTER/,/^$/p' "$work/out.txt" \
  | grep -E '^  [a-z-]+$' | tr -d ' ' | sort | tr '\n' ','; } || true )"
check "exactly the unroutable roles" "coding,default,quickest,small," "$reported"

# (B) the local endpoint listed no aliases at all and must not be blamed for it.
check "local endpoint not blamed" "yes" \
  "$(grep -q 'not addressable at local' "$work/out.txt" && echo no || echo yes)"

# ---- (B) full local exemption, clean router -----------------------------
# Same local listing (ids only, zero aliases) but the router addresses every
# role. Nothing is drifting, so this must be a clean pass — this is the case the
# earlier draft failed, reporting every role broken.
echo "(B) aliases absent from /v1/models is not drift"
write_registry "$work/reg-b.json" $ROLES
set_endpoints "$work/reg-b.json" "http://127.0.0.1:$port/v1" "http://127.0.0.1:$port/v1"
write_models "$THE_MODEL"
write_info "$THE_MODEL" $ROLES
run_check "$work/reg-b.json"
check "exit status" "0" "$rc"
check "declares no drift" "yes" \
  "$(grep -q 'no drift' "$work/out.txt" && echo yes || echo no)"

# ---- (C) nothing reachable is not an all-clear --------------------------
# Both endpoints point at a port nothing listens on. Port 1 is privileged and
# unbound in every sandbox this runs in, so the connection is refused rather
# than hanging.
echo "(C) no endpoint reachable"
write_registry "$work/reg-c.json" $ROLES
set_endpoints "$work/reg-c.json" "http://127.0.0.1:1/v1" "http://127.0.0.1:1/v1"
run_check "$work/reg-c.json"
check "exit status" "2" "$rc"
check "says it verified nothing" "yes" \
  "$(grep -q 'VERIFIED NOTHING' "$work/out.txt" && echo yes || echo no)"
check "does NOT claim no drift" "yes" \
  "$(grep -q 'no drift' "$work/out.txt" && echo no || echo yes)"

# ---- model-id drift still reported --------------------------------------
# The original purpose, kept fenced: a role whose model resolves locally but not
# at the router is breakage for every routed caller.
echo "(E) model resolves locally but not at the router"
write_registry "$work/reg-e.json" $ROLES
set_endpoints "$work/reg-e.json" "http://127.0.0.1:$port/v1" "http://127.0.0.1:$port/v1"
write_models "$THE_MODEL"
write_info "$OTHER_MODEL" $ROLES
run_check "$work/reg-e.json"
check "exit status" "1" "$rc"
check "reports the one-endpoint heading" "yes" \
  "$(grep -q 'MODEL RESOLVES AT ONLY ONE ENDPOINT' "$work/out.txt" && echo yes || echo no)"

# ---- missing registry ----------------------------------------------------
echo "(F) missing registry"
run_check "$work/does-not-exist.json"
check "exit status" "2" "$rc"

if [ "$fail" -ne 0 ]; then
  echo "FAILED"
  exit 1
fi
echo "all ai-stack-drift-check tests passed"
