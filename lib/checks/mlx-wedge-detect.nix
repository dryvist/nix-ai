# llama-swap slot-accounting wedge auto-recovery (nix-ai#1300, Zammad AI/LLM
# Serving INC-17114). Two layers, matching the two things that can break:
#
#   mlx-wedge-classify — the pure two-condition discriminator (wedge_classify
#     in scripts/wedge-detect.sh) run directly via tests/test-wedge-classify.sh.
#     No mocks; it is a scalar-in/scalar-out function.
#   mlx-wedge-recovery — the orchestration (check_wedge), run against the
#     SAME concatenation mlx-watchdog-pkg.nix ships (llama-swap-reap.sh, then
#     wedge-detect.sh, then mlx-watchdog.sh) — check_wedge and
#     mlx_reap_orphan_ports do not exist in the raw watchdog file alone, so
#     this must run the built shape, not the standalone script.
#     Its own minimal curl/date/sleep fakes are separate from
#     mlx-watchdog.nix's, so this cannot destabilize that file's scenarios.
#     Proves: the persistence streak waits for MLX_WATCHDOG_WEDGE_CONSECUTIVE
#     observations before acting; a confirmed wedge reaches escalate_ladder's
#     rung-1 reap-then-kickstart; and a wedge that keeps re-firing inside the
#     incident window is HELD (alerted, not restarted again) once
#     MLX_WATCHDOG_WEDGE_INCIDENT_MAX is exceeded, rather than cold-reloading
#     both residents forever.
{ pkgs, src }:
let
  fakeCurl = pkgs.writeShellScriptBin "curl" ''
    body_file="" url="" wfmt=""
    while (( $# > 0 )); do
      case "$1" in
        -o) body_file="$2"; shift 2 ;;
        -w) wfmt="$2"; shift 2 ;;
        --max-time | -H | -d) shift 2 ;;
        *) url="$1"; shift ;;
      esac
    done
    code=""
    case "$url" in
      */chat/completions)
        : > "$body_file"
        code=429
        ;;
      */running)
        printf '{"running":[{"model":"brain-physical","state":"ready","proxy":"http://127.0.0.1:11437"}]}'
        exit 0
        ;;
      http://127.0.0.1:11437/metrics)
        printf 'vllm_mlx_engine_steps_executed %s\n' "$(<"$FAKE_STEPS_FILE")"
        printf 'vllm_mlx_engine_uptime_seconds %s\n' "$(<"$FAKE_UPTIME_FILE")"
        exit 0
        ;;
      *)
        exit 1
        ;;
    esac
    if [[ "$wfmt" == *time_total* ]]; then
      printf '%s %s' "$code" "$(<"$FAKE_LATENCY_S_FILE")"
    else
      printf '%s' "$code"
    fi
  '';
  fakeDate = pkgs.writeShellScriptBin "date" ''
    if [[ "$*" == "+%s" ]]; then cat "$FAKE_NOW_FILE"; else printf 'test-time\n'; fi
  '';
  fakeSleep = pkgs.writeShellScriptBin "sleep" "exit 0";
  # reap_workers() now calls mlx_reap_orphan_ports (llama-swap-reap.sh,
  # nix-ai#1423) instead of a pgrep/pkill pattern. A holder-free lsof is all
  # this check needs: mlx_reap_orphan_ports returns immediately without ever
  # calling kill, so no fake kill is required either.
  fakeLsof = pkgs.writeShellScriptBin "fake-lsof" "exit 1";
in
{
  mlx-wedge-classify = pkgs.runCommand "check-mlx-wedge-classify" {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
    ];
  } "bash ${src}/tests/test-wedge-classify.sh && touch $out";

  mlx-wedge-recovery = pkgs.runCommand "check-mlx-wedge-recovery" { } ''
    export PATH=${fakeCurl}/bin:${fakeDate}/bin:${fakeSleep}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gawk}/bin:${pkgs.jq}/bin:${pkgs.gnugrep}/bin
    export HOME="$TMPDIR/home"
    export MLX_API_URL=http://127.0.0.1:11434/v1
    export MLX_LAUNCHD_LABEL=dev.test.mlx
    export MLX_LSOF_BIN=${fakeLsof}/bin/fake-lsof
    export MLX_PORT=11434
    export MLX_WORKER_PORT_RANGE_START=11436
    export MLX_WORKER_PORT_COUNT=2
    export MLX_WATCHDOG_PROBE_MODELS_JSON='["tool-calling"]'
    export MLX_WATCHDOG_BRAIN_MODEL=tool-calling
    export MLX_WATCHDOG_COOLDOWN=90
    export MLX_WATCHDOG_CONFIG="$TMPDIR/llama-swap.json"
    export MLX_WATCHDOG_MARKER="$TMPDIR/last-kick"
    export MLX_WATCHDOG_FAIL_MARKER="$TMPDIR/failures"
    export MLX_WATCHDOG_BUSY_MARKER="$TMPDIR/busy-since"
    export MLX_WATCHDOG_PROGRESS_MARKER="$TMPDIR/progress-marker"
    export MLX_WATCHDOG_WEDGE_MARKER="$TMPDIR/wedge-suspect"
    export MLX_WATCHDOG_WEDGE_LATENCY_MS=500
    export MLX_WATCHDOG_WEDGE_CONSECUTIVE=2
    export MLX_WATCHDOG_WEDGE_INCIDENT_MARKER="$TMPDIR/wedge-incidents"
    export MLX_WATCHDOG_WEDGE_INCIDENT_WINDOW=3600
    export MLX_WATCHDOG_WEDGE_INCIDENT_MAX=3
    export MLX_WATCHDOG_ALERT_URL_FILE="$TMPDIR/no-alert"
    export MLX_WATCHDOG_HEALTHCHECK_URL_FILE="$TMPDIR/no-healthcheck"
    export FAKE_NOW_FILE="$TMPDIR/now"
    export FAKE_STEPS_FILE="$TMPDIR/steps"
    export FAKE_UPTIME_FILE="$TMPDIR/uptime"
    export FAKE_LATENCY_S_FILE="$TMPDIR/latency"

    # Same concatenation mlx-watchdog-pkg.nix ships: check_wedge only exists
    # once wedge-detect.sh is ahead of mlx-watchdog.sh in one script, and
    # reap_workers() (hit by escalate_ladder below) only resolves
    # mlx_reap_orphan_ports once llama-swap-reap.sh is ahead of that
    # (nix-ai#1423).
    combined="$TMPDIR/mlx-watchdog-combined.sh"
    cat ${src}/modules/mlx/scripts/llama-swap-reap.sh ${src}/modules/mlx/scripts/wedge-detect.sh ${src}/modules/mlx/scripts/mlx-watchdog.sh > "$combined"

    printf '%s\n' '{"models":{"brain-physical":{"aliases":["tool-calling"]}}}' > "$MLX_WATCHDOG_CONFIG"
    printf '1\n' > "$MLX_WATCHDOG_MARKER"
    printf '0.004\n' > "$FAKE_LATENCY_S_FILE"
    printf '11\n' > "$FAKE_STEPS_FILE"
    printf '1001\n' > "$FAKE_UPTIME_FILE"

    tick() { bash "$combined" > "$1" 2>&1; }

    echo "tick 1: fast 429 + flat steps, but only ONE observation -> must NOT act yet"
    printf '20000\n' > "$FAKE_NOW_FILE"
    tick "$TMPDIR/wedge-1.log"
    grep -q 'WEDGE SUSPECT streak 1/2' "$TMPDIR/wedge-1.log"
    if grep -q 'kickstart' "$TMPDIR/wedge-1.log"; then
      echo "FAIL: kickstart fired on a single observation" >&2; exit 1
    fi
    test "$(<"$MLX_WATCHDOG_WEDGE_MARKER")" = 1

    echo "tick 2: same signature persists -> escalate via the shared ladder (incident 1/3)"
    printf '20200\n' > "$FAKE_NOW_FILE"
    tick "$TMPDIR/wedge-2.log"
    grep -q 'WEDGE SUSPECT streak 2/2' "$TMPDIR/wedge-2.log"
    grep -q 'incident 1/3' "$TMPDIR/wedge-2.log"
    grep -q 'reap + kickstart' "$TMPDIR/wedge-2.log"
    test ! -e "$MLX_WATCHDOG_WEDGE_MARKER"

    # The "engine steps advanced between probes -> never restart real work"
    # branch is a property of wedge_classify itself (pure, no timing, no
    # curl), already asserted directly by test-wedge-classify.sh above via
    # mlx-wedge-classify. Re-deriving it here would need a curl fake that
    # returns a different value on its 2nd-vs-1st call within one tick, which
    # this harness's fakeCurl deliberately does not model.

    # incidents 2 and 3: the defect keeps re-leaking -> the shared ladder
    # keeps firing (rung climbs to bootout+bootstrap on the 2nd+ failure —
    # fail_marker is deliberately NOT cleared by the wedge path, so it shares
    # rung memory with the coarse dead/down path; only "not held" and
    # "the ladder actually ran" are asserted here, not the exact rung wording,
    # since that is the existing coarse escalate_ladder's own contract).
    echo "incidents 2 and 3: the defect keeps re-leaking -> the ladder keeps firing"
    printf '20400\n' > "$FAKE_NOW_FILE"
    tick "$TMPDIR/wedge-3.log"
    printf '20600\n' > "$FAKE_NOW_FILE"
    tick "$TMPDIR/wedge-4.log"
    grep -q 'incident 2/3' "$TMPDIR/wedge-4.log"
    grep -q 'failure' "$TMPDIR/wedge-4.log"
    if grep -q 'HOLDING' "$TMPDIR/wedge-4.log"; then
      echo "FAIL: held before incident_max was exceeded" >&2; exit 1
    fi

    printf '20800\n' > "$FAKE_NOW_FILE"
    tick "$TMPDIR/wedge-5.log"
    printf '21000\n' > "$FAKE_NOW_FILE"
    tick "$TMPDIR/wedge-6.log"
    grep -q 'incident 3/3' "$TMPDIR/wedge-6.log"
    grep -q 'failure' "$TMPDIR/wedge-6.log"
    if grep -q 'HOLDING' "$TMPDIR/wedge-6.log"; then
      echo "FAIL: held before incident_max was exceeded" >&2; exit 1
    fi

    echo "incident 4 within the same window: HELD, not restarted again"
    printf '21200\n' > "$FAKE_NOW_FILE"
    tick "$TMPDIR/wedge-7.log"
    printf '21400\n' > "$FAKE_NOW_FILE"
    tick "$TMPDIR/wedge-8.log"
    grep -q 'WEDGE SUSPECT streak 2/2' "$TMPDIR/wedge-8.log"
    grep -q 'HOLDING, NOT restarting again' "$TMPDIR/wedge-8.log"
    if grep -qE 'kickstart|bootout' "$TMPDIR/wedge-8.log"; then
      echo "FAIL: recovery fired while held" >&2; exit 1
    fi
    grep -q "page NOT sent: .*held, NOT restarting again" "$TMPDIR/wedge-8.log"

    touch "$out"
  '';
}
