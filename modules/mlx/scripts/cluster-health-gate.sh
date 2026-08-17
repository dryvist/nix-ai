# shellcheck shell=bash
# Cluster link watcher — automated rank health gate + soak.
#
# Concatenated ahead of cluster-link-watcher.sh, after cluster-link-guards.sh
# (this file calls that one's mem_stat_mb). Function definitions only, same
# rules as every other file in this layer.
#
# WHY THIS FILE EXISTS. Until now "the rank is ready to serve" meant one
# untimed 1-token warm generation succeeded once. That is the manual gate a
# human ran by hand every night before trusting a window: /v1/models answers,
# a real completion returns real tokens inside a real timeout, the endpoint
# holds up under the concurrency the proxy actually offers it
# (proxy.concurrencyLimit), and the host is not already over its wired
# ceiling. Encoding that here removes the human from the loop entirely instead
# of leaving one more "looked fine, run it anyway" judgment call.
#
# Consumed environment (coordinator only — see cluster-watcher-env.nix):
#   CLUSTER_HEALTH_GATE_TIMEOUT_SECS  bound on one 1-token completion (probes
#                                  b and the soak recheck)
#   CLUSTER_HEALTH_GATE_CONCURRENCY  N concurrent completions for probe c
#   CLUSTER_HEALTH_GATE_CONCURRENT_TIMEOUT_SECS  bound on EACH of those N
#   CLUSTER_WIRED_LIMIT_MB          probe d's ceiling; 0/unset skips it (same
#                                  "0 = off" convention as the memory rung)
#
# Sets HEALTH_GATE_DETAIL on any probe failure, for the caller's log line.

# Probe (a): the endpoint answers at all.
health_gate_probe_models() {
  local url="$1"
  if curl -fsS -m 10 -o /dev/null "$url/v1/models" 2>/dev/null; then
    return 0
  fi
  HEALTH_GATE_DETAIL="/v1/models did not return 200 within 10s"
  return 1
}

# Probe (b): one real completion, a real timeout, and a body that is actually
# there — `curl -f` alone accepts a 200 with an empty body, which is exactly
# what a wedged rank behind a proxy can return. Reused verbatim by the soak
# recheck below, so "ready" and "still alive" are judged by one definition.
health_gate_probe_completion() {
  local url="$1" model="$2" timeout="$3" body_file rc=1
  body_file="$(mktemp)"
  # No RETURN trap: it is not function-scoped — it re-fires on every LATER
  # function return in the same shell, including callers with no body_file of
  # their own, which is exactly the "unbound variable" this file's own test
  # caught. Manual cleanup on every exit path instead.
  if curl -fsS -m "$timeout" -X POST "$url/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"warmup\"}],\"max_tokens\":1,\"stream\":false,\"temperature\":0}" \
    -o "$body_file" 2>/dev/null && [ -s "$body_file" ]; then
    rc=0
  else
    HEALTH_GATE_DETAIL="1-token completion failed or returned an empty body within ${timeout}s"
  fi
  rm -f "$body_file"
  return "$rc"
}

# Probe (c): N completions in flight together, matching the proxy's own
# concurrency ceiling (proxy.concurrencyLimit) instead of a single request at
# a time — a rank can answer one request fine and still fall over the moment
# real traffic overlaps it.
health_gate_probe_concurrent() {
  local url="$1" model="$2" n="$3" timeout="$4" i pid f passed=0
  local pids=() ok_files=()
  for ((i = 0; i < n; i++)); do
    ok_files[i]="$(mktemp)"
    (health_gate_probe_completion "$url" "$model" "$timeout" && echo pass > "${ok_files[i]}") &
    pids[i]=$!
  done
  for pid in "${pids[@]}"; do wait "$pid" || true; done
  for f in "${ok_files[@]}"; do
    [ "$(cat "$f" 2>/dev/null)" = "pass" ] && passed=$((passed + 1))
    rm -f "$f"
  done
  [ "$passed" -eq "$n" ] && return 0
  HEALTH_GATE_DETAIL="$passed/$n concurrent completions returned non-empty 200 within ${timeout}s"
  return 1
}

# Probe (d): reuses mem_stat_mb (cluster-link-guards.sh, concatenated ahead of
# this file) rather than a second vm_stat read — one measurement, one page-size
# parse, one place that can be wrong.
health_gate_probe_wired() {
  local ceiling="$1" stat_out wired
  case "$ceiling" in
    '' | *[!0-9]*) return 0 ;;
  esac
  [ "$ceiling" -gt 0 ] || return 0
  if ! stat_out="$(mem_stat_mb)"; then
    HEALTH_GATE_DETAIL="could not read vm_stat; refusing to guess whether the host is over ceiling"
    return 1
  fi
  # mem_stat_mb prints "<free> <wired>"; only the second field is needed here.
  wired="${stat_out#* }"
  [ "$wired" -le "$ceiling" ] && return 0
  # shellcheck disable=SC2034 # read by cluster-link-watcher.sh's log/halt/alert
  # lines, same sourced layer (cluster-script-layers.nix's `watcher`)
  HEALTH_GATE_DETAIL="${wired}MB wired against a ${ceiling}MB ceiling"
  return 1
}

# The full gate, run once when the rank first reaches readiness. $1 = state
# file (evidence log, appended forever — never truncated, same as every other
# marker in this dir). Returns 0 only if every probe passed; always writes one
# evidence line either way, because "the gate ran and what it saw" is the
# audit trail a wedged window used to have none of.
health_gate_run() {
  local state_file="$1" url="$2" model="$3" timeout="$4" n="$5" \
    concurrent_timeout="$6" ceiling="$7"
  local models_ok=FAIL completion_ok=FAIL concurrent_ok=FAIL wired_ok=FAIL verdict=FAIL
  health_gate_probe_models "$url" && models_ok=PASS
  health_gate_probe_completion "$url" "$model" "$timeout" && completion_ok=PASS
  health_gate_probe_concurrent "$url" "$model" "$n" "$concurrent_timeout" && concurrent_ok=PASS
  health_gate_probe_wired "$ceiling" && wired_ok=PASS
  if [ "$models_ok" = PASS ] && [ "$completion_ok" = PASS ] &&
    [ "$concurrent_ok" = PASS ] && [ "$wired_ok" = PASS ]; then
    verdict=PASS
  fi
  printf '%s\tGATE\tmodels=%s completion=%s concurrent=%s wired=%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$models_ok" "$completion_ok" \
    "$concurrent_ok" "$wired_ok" "$verdict" >> "$state_file"
  [ "$verdict" = PASS ]
}

# Soak: probe (b) alone, on the recheck interval, appended to the same log.
# Deliberately lighter than health_gate_run — re-running the full N-way
# concurrent probe every ~10 minutes would compete with real traffic for the
# same proxy concurrency slot it is trying to verify is healthy.
health_gate_soak_probe() {
  local state_file="$1" url="$2" model="$3" timeout="$4"
  local ok=FAIL
  health_gate_probe_completion "$url" "$model" "$timeout" && ok=PASS
  printf '%s\tSOAK\tcompletion=%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ok" "$ok" >> "$state_file"
  [ "$ok" = PASS ]
}
