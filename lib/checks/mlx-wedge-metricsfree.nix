# litellm/mlx — metrics-free wedge detection and per-model recovery.
#
# Split out of lib/checks/mlx-wedge-detect.nix for the per-file 12KB gate (the
# repo's split-rather-than-exempt pattern; see the split history of
# modules/mlx/options and lib/checks/mlx-proxy-logging.nix). Its fakes are
# declared here rather than shared, because this check needs a curl that
# branches per model -- the sibling file's fake answers 429 for everything,
# which cannot express "one model wedged while another serves".
{ pkgs, src }:
let
  fakeDate = pkgs.writeShellScriptBin "date" ''
    if [[ "$*" == "+%s" ]]; then cat "$FAKE_NOW_FILE"; else printf 'test-time\n'; fi
  '';
  fakeSleep = pkgs.writeShellScriptBin "sleep" "exit 0";
  fakeLsof = pkgs.writeShellScriptBin "fake-lsof" "exit 1";
  # Unlike fakeCurl (429 for everything), this one branches on the model in the
  # -d payload so a healthy SIBLING can exist alongside a wedged model -- the
  # exact condition the metrics-free detector keys on.
  fakeCurlPerModel = pkgs.writeShellScriptBin "curl" ''
    body_file="" url="" wfmt="" payload=""
    while (( $# > 0 )); do
      case "$1" in
        -o) body_file="$2"; shift 2 ;;
        -w) wfmt="$2"; shift 2 ;;
        -d) payload="$2"; shift 2 ;;
        --max-time | -H) shift 2 ;;
        *) url="$1"; shift ;;
      esac
    done
    code=""
    case "$url" in
      */chat/completions)
        case "$payload" in
          *stuck-model*)
            : > "$body_file"; code=429 ;;
          *)
            printf '{"usage":{"completion_tokens":4}}' > "$body_file"; code=200 ;;
        esac
        ;;
      */running)
        printf '{"running":[{"model":"brain-physical","state":"ready","proxy":"http://127.0.0.1:11437"}]}'
        exit 0
        ;;
      */api/models/unload/*)
        printf '%s\n' "''${url##*/unload/}" >> "$UNLOAD_LOG"
        exit 0
        ;;
      *) exit 1 ;;
    esac
    if [[ "$wfmt" == *time_total* ]]; then
      printf '%s %s' "$code" "0.004"
    else
      printf '%s' "$code"
    fi
  '';

in
{
  # The metrics-free wedge page. check_wedge returns on its first line whenever
  # the backend publishes no engine metrics (busy_escalation != "restart"),
  # which is every mlx-lm host -- so a model refusing 100% of arrivals stayed
  # classified `busy`, documented as "NOT a failure", and never paged. A
  # resident model was observed refusing every request for a day in silence.
  #
  # The discriminator needing no metrics is a healthy SIBLING on the same
  # proxy. This asserts BOTH directions: no page before the streak is met, and
  # a page once it is. Page only -- it must never restart on this path.
  mlx-wedge-metricsfree = pkgs.runCommand "check-mlx-wedge-metricsfree" { } ''
    export PATH=${fakeCurlPerModel}/bin:${fakeDate}/bin:${fakeSleep}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gawk}/bin:${pkgs.jq}/bin:${pkgs.gnugrep}/bin
    export HOME="$TMPDIR/home"
    export MLX_API_URL=http://127.0.0.1:11434/v1
    export MLX_LAUNCHD_LABEL=dev.test.mlx
    export MLX_LSOF_BIN=${fakeLsof}/bin/fake-lsof
    export MLX_PORT=11434
    export MLX_WORKER_PORT_RANGE_START=11436
    export MLX_WORKER_PORT_COUNT=2
    export MLX_WATCHDOG_PROBE_MODELS_JSON='["tool-calling","stuck-model"]'
    export MLX_WATCHDOG_BRAIN_MODEL=tool-calling
    # The gate that makes check_wedge return immediately -- the whole point.
    export MLX_WATCHDOG_BUSY_ESCALATION=alert
    export MLX_WATCHDOG_COOLDOWN=90
    export MLX_WATCHDOG_CONFIG="$TMPDIR/llama-swap.json"
    export MLX_WATCHDOG_MARKER="$TMPDIR/last-kick"
    export MLX_WATCHDOG_FAIL_MARKER="$TMPDIR/failures"
    export MLX_WATCHDOG_BUSY_MARKER="$TMPDIR/busy-since"
    export MLX_WATCHDOG_PROGRESS_MARKER="$TMPDIR/progress-marker"
    export MLX_WATCHDOG_WEDGE_MARKER="$TMPDIR/wedge-suspect"
    export MLX_WATCHDOG_WEDGE_INCIDENT_MARKER="$TMPDIR/wedge-incidents"
    export MLX_WATCHDOG_STUCK_BUSY_DIR="$TMPDIR/stuck-busy"
    export MLX_WATCHDOG_STUCK_BUSY_CONSECUTIVE=3
    export MLX_WATCHDOG_STUCK_BUSY_RECOVER_MAX=2
    export UNLOAD_LOG="$TMPDIR/unloads"
    : > "$UNLOAD_LOG"
    export MLX_WATCHDOG_ALERT_URL_FILE="$TMPDIR/no-alert"
    export MLX_WATCHDOG_HEALTHCHECK_URL_FILE="$TMPDIR/no-healthcheck"
    export FAKE_NOW_FILE="$TMPDIR/now"
    export FAKE_STEPS_FILE="$TMPDIR/steps"
    export FAKE_UPTIME_FILE="$TMPDIR/uptime"
    export FAKE_LATENCY_S_FILE="$TMPDIR/latency"

    combined="$TMPDIR/mlx-watchdog-combined.sh"
    cat ${src}/modules/mlx/scripts/llama-swap-reap.sh ${src}/modules/mlx/scripts/wedge-detect.sh ${src}/modules/mlx/scripts/mlx-watchdog.sh > "$combined"

    printf '%s\n' '{"models":{"brain-physical":{"aliases":["tool-calling"]}}}' > "$MLX_WATCHDOG_CONFIG"
    printf '1\n' > "$MLX_WATCHDOG_MARKER"
    printf '0.004\n' > "$FAKE_LATENCY_S_FILE"
    printf '11\n' > "$FAKE_STEPS_FILE"
    printf '1001\n' > "$FAKE_UPTIME_FILE"
    printf '20000\n' > "$FAKE_NOW_FILE"

    tick() { bash "$combined" > "$1" 2>&1 || true; }

    echo "check_wedge must skip on a metrics-free backend"
    tick "$TMPDIR/t1.log"
    grep -q 'no engine-progress metric' "$TMPDIR/t1.log"

    echo "ticks 1-2: below the streak -> watching, NEVER a page"
    grep -q 'busy 1/3' "$TMPDIR/t1.log"
    if grep -q 'WEDGE (metrics-free)' "$TMPDIR/t1.log"; then
      echo "FAIL: paged on the first observation"; exit 1
    fi
    tick "$TMPDIR/t2.log"
    grep -q 'busy 2/3' "$TMPDIR/t2.log"
    if grep -q 'WEDGE (metrics-free)' "$TMPDIR/t2.log"; then
      echo "FAIL: paged before the streak was met"; exit 1
    fi

    echo "tick 3: streak met with a healthy sibling -> page, and NO restart"
    tick "$TMPDIR/t3.log"
    grep -q 'WEDGE (metrics-free) model=stuck-model' "$TMPDIR/t3.log"
    grep -q 'sibling=tool-calling' "$TMPDIR/t3.log"
    if grep -qE 'kickstart|bootout' "$TMPDIR/t3.log"; then
      echo "FAIL: metrics-free path must PAGE, never restart"; exit 1
    fi

    echo "tick 3 must also RECOVER: unload that model only, never the sibling"
    grep -q 'unloaded wedged model stuck-model' "$TMPDIR/t3.log"
    grep -q 'stuck-model' "$UNLOAD_LOG"
    if grep -q 'tool-calling' "$UNLOAD_LOG"; then
      echo "FAIL: unloaded the healthy sibling"; exit 1
    fi

    echo "a successful unload clears the streak, so detection restarts"
    tick "$TMPDIR/t4.log"
    grep -q 'busy 1/3' "$TMPDIR/t4.log"

    echo "recovery is BOUNDED: second unload allowed, third refused"
    tick "$TMPDIR/t5.log"; tick "$TMPDIR/t6.log"
    grep -q 'recovery 2/2' "$TMPDIR/t6.log"
    tick "$TMPDIR/t7.log"; tick "$TMPDIR/t8.log"; tick "$TMPDIR/t9.log"
    grep -q 'NOT unloading again' "$TMPDIR/t9.log"
    grep -q 'alerting only' "$TMPDIR/t9.log"
    if [[ "$(grep -c . "$UNLOAD_LOG")" != "2" ]]; then
      echo "FAIL: expected exactly 2 unloads, got $(grep -c . "$UNLOAD_LOG")"; exit 1
    fi

    touch $out
  '';
}
