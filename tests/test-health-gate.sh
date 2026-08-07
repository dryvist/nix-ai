#!/usr/bin/env bash
# Exercises the automated rank health gate + soak (vk1188,
# modules/mlx/scripts/cluster-health-gate.sh) — the check that replaces the
# human who used to run this by hand every night before trusting a window.
#
# WHY THIS EXISTS. The old gate was one untimed 1-token warm generation.
# vk1188 replaces it with four probes — /v1/models answers, one real
# completion inside a real timeout with a non-empty body, N of those AT ONCE
# (matching the proxy's own concurrency ceiling), and the host is not already
# over its wired ceiling — plus a periodic soak recheck once the gate has
# passed. This is the test that fails if any probe stops actually gating, or
# if a failure stops reaching the halt path.
#
# WHAT IS REAL AND WHAT IS NOT:
#   REAL  — every health_gate_* function is sourced from the shipped script
#           and called exactly as the watcher calls it.
#   STUB  — curl, as a shell FUNCTION (the shipped code calls it by plain
#           name from within this same sourced process, so a function
#           shadows it — same idiom test-mem-headroom.sh uses for curl in
#           alert()). vm_stat as a generated executable on CLUSTER_VMSTAT_BIN,
#           same reason and same fixture writer as test-mem-headroom.sh.
#
# Usage:
#   GUARDS=… GATE=… bash test-health-gate.sh
set -o errexit -o nounset -o pipefail

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT

# shellcheck disable=SC1090
source "${GUARDS:?set GUARDS to cluster-link-guards.sh}"
# shellcheck disable=SC1090
source "${GATE:?set GATE to cluster-health-gate.sh}"

# --- vm_stat stub, generated executable (see test-mem-headroom.sh) ---------
bin="$state_dir/bin"
mkdir -p "$bin"
vmstat_fixture="$state_dir/vmstat-output"
vmstat_rc="$state_dir/vmstat-rc"
cat > "$bin/vm_stat" << VMSTAT
#!$BASH
forced="\$(cat '$vmstat_rc' 2>/dev/null || true)"
if [ -n "\$forced" ]; then exit "\$forced"; fi
cat '$vmstat_fixture'
VMSTAT
chmod +x "$bin/vm_stat"
export CLUSTER_VMSTAT_BIN="$bin/vm_stat"

write_vmstat() {
  local wired="$1"
  cat > "$vmstat_fixture" << EOF
Mach Virtual Memory Statistics: (page size of 4096 bytes)
Pages free:                              256000.
Pages active:                            1000.
Pages inactive:                          1000.
Pages speculative:                       1000.
Pages throttled:                         0.
Pages wired down:                        ${wired}.
Pages purgeable:                         0.
EOF
}
write_vmstat 0

# --- curl stub, a shell FUNCTION (see header) -------------------------------
# Controlled per request kind via three files: models_rc gates the /v1/models
# probe, completion_rc + completion_body gate every /v1/chat/completions call
# (probe b, every concurrent leg of probe c, and every soak recheck alike —
# they are all the same underlying probe function).
models_rc="$state_dir/models-rc"
completion_rc="$state_dir/completion-rc"
completion_body="$state_dir/completion-body"
echo 0 > "$models_rc"
echo 0 > "$completion_rc"
echo '{"choices":[{"text":"ok"}]}' > "$completion_body"
curl() {
  local out="" is_completion=0 a
  for a in "$@"; do
    case "$a" in
      */v1/chat/completions) is_completion=1 ;;
    esac
  done
  # -o FILE is always the argument immediately following it in every call
  # this file makes.
  local prev=""
  for a in "$@"; do
    [ "$prev" = "-o" ] && out="$a"
    prev="$a"
  done
  if [ "$is_completion" = 1 ]; then
    [ -n "$out" ] && cat "$completion_body" > "$out"
    return "$(cat "$completion_rc")"
  fi
  return "$(cat "$models_rc")"
}

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
reset() {
  echo 0 > "$models_rc"
  echo 0 > "$completion_rc"
  echo '{"choices":[{"text":"ok"}]}' > "$completion_body"
  write_vmstat 0
}

url="http://127.0.0.1:9"
model="test-model"

echo "--- probe (a): /v1/models ---"
reset
health_gate_probe_models "$url" && got=pass || got=fail
check "models healthy" pass "$got"
echo 1 > "$models_rc"
health_gate_probe_models "$url" && got=pass || got=fail
check "models non-200" fail "$got"

echo "--- probe (b): 1-token completion ---"
reset
health_gate_probe_completion "$url" "$model" 5 && got=pass || got=fail
check "completion healthy" pass "$got"
echo 1 > "$completion_rc"
health_gate_probe_completion "$url" "$model" 5 && got=pass || got=fail
check "completion curl failure" fail "$got"
reset
: > "$completion_body"
health_gate_probe_completion "$url" "$model" 5 && got=pass || got=fail
check "completion empty body (200 but nothing to serve)" fail "$got"

echo "--- probe (c): N concurrent completions ---"
reset
health_gate_probe_concurrent "$url" "$model" 2 5 && got=pass || got=fail
check "concurrent all healthy" pass "$got"
echo 1 > "$completion_rc"
health_gate_probe_concurrent "$url" "$model" 2 5 && got=pass || got=fail
check "concurrent all failing" fail "$got"

echo "--- probe (d): wired vs ceiling ---"
reset
write_vmstat 1000
health_gate_probe_wired 90000 && got=pass || got=fail
check "wired under ceiling" pass "$got"
write_vmstat 25600000
health_gate_probe_wired 90000 && got=pass || got=fail
check "wired over ceiling refuses" fail "$got"
health_gate_probe_wired 0 && got=pass || got=fail
check "ceiling 0 disables the rung with no refusal" pass "$got"

echo "--- health_gate_run: overall verdict + evidence ---"
reset
gate_file="$state_dir/health-gate"
health_gate_run "$gate_file" "$url" "$model" 5 2 5 90000 && got=pass || got=fail
check "full gate all healthy" pass "$got"
check "evidence line written" 1 "$(wc -l < "$gate_file" | tr -d ' ')"
check "evidence verdict PASS" 1 "$(grep -c $'\tPASS$' "$gate_file" | tr -d ' ')"

echo 1 > "$completion_rc"
health_gate_run "$gate_file" "$url" "$model" 5 2 5 90000 && got=pass || got=fail
check "full gate one probe failing" fail "$got"
check "second evidence line appended, not overwritten" 2 "$(wc -l < "$gate_file" | tr -d ' ')"

echo "--- health_gate_soak_probe: probe (b) only, appended ---"
reset
soak_file="$state_dir/soak"
health_gate_soak_probe "$soak_file" "$url" "$model" 5 && got=pass || got=fail
check "soak healthy" pass "$got"
echo 1 > "$completion_rc"
health_gate_soak_probe "$soak_file" "$url" "$model" 5 && got=pass || got=fail
check "soak failing" fail "$got"
check "soak evidence has one line per call" 2 "$(wc -l < "$soak_file" | tr -d ' ')"

exit "$fail"
