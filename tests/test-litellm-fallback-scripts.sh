#!/usr/bin/env bash
# Regression tests for the two litellm-local fallback scripts.
#
# (A) litellm-fallback-probe must ask the proxy NOT to fall back. Without that,
#     LiteLLM's own chain answers for the rung under test — a request addressed
#     to a dead rung is served by the next one and still returns 200, so the
#     probe declares a chain healthy while a rung is gone. Asserted on the wire
#     against a stub proxy rather than by grepping the source, because what
#     matters is the field the proxy actually receives.
#
# (B) litellm-fallback-watch's read_int must always yield an integer. A state
#     file holding `08` used to abort the watcher with an invalid-octal
#     arithmetic error: the streak never incremented and the watcher could
#     never page, so a genuinely dead rung stayed invisible. Empty and
#     whitespace files survived only by accident (`$(( + 1 ))` evaluates to 1),
#     so they are fenced here too.
set -o errexit -o nounset -o pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="$repo_root/modules/scripts/litellm-fallback-probe.sh"
WATCH="$repo_root/modules/scripts/litellm-fallback-watch.sh"

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
        body = json.dumps({"model": json.loads(raw)["model"],
                           "choices": [{"finish_reason": "stop",
                                        "message": {"content": "OK"}}]}).encode()
        self.send_response(200)
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

# ---- (B) read_int always yields an integer --------------------------------
state="$work/state"
mkdir -p "$state"

# The watcher's failure branch prints "probe failed N/M"; N is read_int + 1.
watch_streak() {
  printf '%s' "$1" > "$state/fallback-probe-failures"
  LITELLM_PROBE_BIN=false \
    LITELLM_WATCH_STATE_DIR="$state" \
    LITELLM_WATCH_CONSECUTIVE=99 \
    bash "$WATCH" 2>&1 | sed -n 's/.*probe failed \([0-9]*\)\/.*/\1/p'
}

echo "a garbage streak file still advances the streak:"
check "empty file" 1 "$(watch_streak '')"
check "whitespace file" 1 "$(watch_streak '   ')"
check "non-numeric file" 1 "$(watch_streak 'wedged')"
# The regression: bash reads a leading zero as octal, so `08` aborted the whole
# watcher under `set -e` before it could count, log, or page.
check "leading-zero file" 9 "$(watch_streak '08')"
check "ordinary value" 4 "$(watch_streak '3')"

rm -f "$state/fallback-probe-failures"
check "missing file" 1 "$(LITELLM_PROBE_BIN=false \
  LITELLM_WATCH_STATE_DIR="$state" LITELLM_WATCH_CONSECUTIVE=99 \
  bash "$WATCH" 2>&1 | sed -n 's/.*probe failed \([0-9]*\)\/.*/\1/p')"

echo "a garbage last-page stamp does not wedge the page path:"
printf '99' > "$state/fallback-probe-failures"
printf '  ' > "$state/fallback-probe-last-page"
LITELLM_PROBE_BIN=false LITELLM_WATCH_STATE_DIR="$state" \
  LITELLM_WATCH_CONSECUTIVE=2 bash "$WATCH" >"$work/page.log" 2>&1 && rc=0 || rc=$?
check "pages rather than aborting" 1 "$rc"
check "wedge reported" 1 "$(grep -c 'WEDGE' "$work/page.log")"

echo "a healthy probe clears a garbage streak:"
printf '  ' > "$state/fallback-probe-failures"
LITELLM_PROBE_BIN=true LITELLM_WATCH_STATE_DIR="$state" \
  bash "$WATCH" >"$work/ok.log" 2>&1
check "reports the no-op" 1 "$(grep -c 'nothing to do' "$work/ok.log")"

exit "$fail"
