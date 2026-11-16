#!/usr/bin/env bash
# Regression tests for litellm-fallback-probe.
#
# (A) litellm-fallback-probe must ask the proxy NOT to fall back. Without that,
#     LiteLLM's own chain answers for the rung under test — a request addressed
#     to a dead rung is served by the next one and still returns 200, so the
#     probe declares a chain healthy while a rung is gone. Asserted on the wire
#     against a stub proxy rather than by grepping the source, because what
#     matters is the field the proxy actually receives.
#
# (B) HTTP 429 from occupied max_parallel_requests slots means the deployment is
#     busy serving traffic, so it reports BUSY and exits 0; real errors (e.g.
#     404 NotFoundError) report FAIL and exit 1.
set -o errexit -o nounset -o pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$repo_root/modules/scripts/litellm-fallback-probe.sh"

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

# ---- (A) the probe disables fallbacks -------------------------------------
# Stub proxy: records every request body, always answers 200. A recorded body
# without disable_fallbacks means the real proxy would be free to fall through.
cat > "$work/stub.py" <<'PY'
import http.server, pathlib, socketserver, sys, json
out = pathlib.Path(sys.argv[1])

class Server(http.server.HTTPServer):
    # http.server's own server_bind calls socket.getfqdn(), a reverse lookup
    # that took 35s on a workstation whose resolver has no answer for the
    # loopback address — the stub then bound long after the test gave up.
    # Nothing here reads server_name, so skip the lookup entirely.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]

class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        raw = self.rfile.read(int(self.headers["content-length"]))
        (out / "bodies.jsonl").open("a").write(raw.decode() + "\n")
        req = json.loads(raw)
        model = req["model"]
        if model == "busy-rung":
            status = 429
            payload = {
                "error": {
                    "message": "litellm.RateLimitError: Deployment has all max_parallel_requests slots in use.",
                    "type": "rate_limit_error",
                    "code": "429",
                }
            }
        elif model == "dead-rung":
            status = 404
            payload = {
                "error": {
                    "message": "litellm.NotFoundError: model group not found",
                    "type": "not_found_error",
                    "code": "404",
                }
            }
        else:
            status = 200
            payload = {
                "model": model,
                "choices": [{"finish_reason": "stop", "message": {"content": "OK"}}],
            }
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
srv = Server(("127.0.0.1", 0), H)
(out / "port").write_text(str(srv.server_port))
srv.serve_forever()
PY
python3 "$work/stub.py" "$work" >"$work/stub.log" 2>&1 &
stub_pid=$!

for _ in $(seq 1 50); do
  [ -s "$work/port" ] && break
  sleep 0.1
done
[ -s "$work/port" ] || {
  echo "FAIL stub proxy never bound a port"
  cat "$work/stub.log" >&2
  exit 1
}

echo "the probe asks the proxy not to fall back:"
LITELLM_LOCAL_URL="http://127.0.0.1:$(cat "$work/port")" \
  bash "$PROBE" rung-under-test >/dev/null
check "disable_fallbacks sent" true \
  "$(python3 -c 'import json,sys; print(json.dumps(json.loads(open(sys.argv[1]).readline()).get("disable_fallbacks")))' "$work/bodies.jsonl")"
check "rung addressed by name" '"rung-under-test"' \
  "$(python3 -c 'import json,sys; print(json.dumps(json.loads(open(sys.argv[1]).readline()).get("model")))' "$work/bodies.jsonl")"

# ---- (B) occupied max_parallel_requests is BUSY (exit 0), 404 still fails ----
echo "the probe treats max_parallel_requests 429 as BUSY, not FAIL:"
busy_out=$(LITELLM_LOCAL_URL="http://127.0.0.1:$(cat "$work/port")" \
  bash "$PROBE" busy-rung 2>&1) && busy_rc=0 || busy_rc=$?
check "busy rung exits 0" 0 "$busy_rc"
check "busy rung reports BUSY" 1 "$(printf '%s\n' "$busy_out" | grep -c 'BUSY')"

echo "the probe still fails on a dead rung:"
dead_out=$(LITELLM_LOCAL_URL="http://127.0.0.1:$(cat "$work/port")" \
  bash "$PROBE" dead-rung 2>&1) && dead_rc=0 || dead_rc=$?
check "dead rung exits 1" 1 "$dead_rc"
check "dead rung reports FAIL" 1 "$(printf '%s\n' "$dead_out" | grep -c 'FAIL')"

exit "$fail"
