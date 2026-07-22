# Deterministic contract for the serving watchdog's busy-progress state.
{ pkgs, src }:
let
  fakeCurl = pkgs.writeShellScriptBin "curl" ''
    body_file=""
    url=""
    while (( $# > 0 )); do
      case "$1" in
        -o)
          body_file="$2"
          shift 2
          ;;
        -w | --max-time | -H | -d)
          shift 2
          ;;
        *)
          url="$1"
          shift
          ;;
      esac
    done
    case "$url" in
      */chat/completions)
        case "$(<"$FAKE_MODE_FILE")" in
          healthy)
            printf '{"usage":{"completion_tokens":1}}' > "$body_file"
            printf '200'
            ;;
          dead)
            printf '{"usage":{"completion_tokens":0}}' > "$body_file"
            printf '200'
            ;;
          *)
            : > "$body_file"
            printf '429'
            ;;
        esac
        ;;
      */running)
        printf '%s' '{"running":['
        printf '%s' '{"model":"brain-physical","state":"ready","proxy":"http://127.0.0.1:11437"},'
        printf '%s' '{"model":"other-physical","state":"ready","proxy":"http://127.0.0.1:11436"}'
        printf '%s' ']}'
        ;;
      http://127.0.0.1:11437/metrics)
        if [[ "$(<"$FAKE_METRICS_MODE_FILE")" == "missing" ]]; then
          printf 'vllm_mlx_inference_requests_total{result="error"} %s\n' "$(<"$FAKE_ERROR_FILE")"
        else
          printf 'vllm_mlx_engine_steps_executed %s\n' "$(<"$FAKE_STEPS_FILE")"
          printf 'vllm_mlx_engine_uptime_seconds %s\n' "$(<"$FAKE_UPTIME_FILE")"
          printf 'vllm_mlx_inference_requests_total{result="error"} %s\n' "$(<"$FAKE_ERROR_FILE")"
        fi
        ;;
      http://127.0.0.1:11436/metrics)
        printf 'vllm_mlx_engine_steps_executed %s\n' "$(<"$FAKE_OTHER_STEPS_FILE")"
        printf 'vllm_mlx_engine_uptime_seconds 9999\n'
        ;;
      *)
        exit 1
        ;;
    esac
  '';
  fakeDate = pkgs.writeShellScriptBin "date" ''
    if [[ "$*" == "+%s" ]]; then
      cat "$FAKE_NOW_FILE"
    else
      printf 'test-time\n'
    fi
  '';
  fakeSleep = pkgs.writeShellScriptBin "sleep" "exit 0";
in
{
  mlx-watchdog-progress = pkgs.runCommand "check-mlx-watchdog-progress" { } ''
    export PATH=${fakeCurl}/bin:${fakeDate}/bin:${fakeSleep}/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.gawk}/bin:${pkgs.gnugrep}/bin:${pkgs.jq}/bin
    export HOME="$TMPDIR/home"
    export MLX_API_URL=http://127.0.0.1:11434/v1
    export MLX_LAUNCHD_LABEL=dev.test.mlx
    export MLX_MODEL_SERVER_PROCESS_PATTERN=vllm_mlx.server
    export MLX_WATCHDOG_PROBE_MODELS_JSON='["tool-calling"]'
    export MLX_WATCHDOG_BRAIN_MODEL=tool-calling
    export MLX_WATCHDOG_BUSY_GRACE=900
    export MLX_WATCHDOG_COOLDOWN=90
    export MLX_WATCHDOG_CONFIG="$TMPDIR/llama-swap.json"
    export MLX_WATCHDOG_MARKER="$TMPDIR/last-kick"
    export MLX_WATCHDOG_FAIL_MARKER="$TMPDIR/failures"
    export MLX_WATCHDOG_BUSY_MARKER="$TMPDIR/busy-since"
    export MLX_WATCHDOG_PROGRESS_MARKER="$TMPDIR/progress-marker"
    export MLX_WATCHDOG_ALERT_URL_FILE="$TMPDIR/no-alert"
    export MLX_WATCHDOG_HEALTHCHECK_URL_FILE="$TMPDIR/no-healthcheck"
    export FAKE_MODE_FILE="$TMPDIR/mode"
    export FAKE_METRICS_MODE_FILE="$TMPDIR/metrics-mode"
    export FAKE_NOW_FILE="$TMPDIR/now"
    export FAKE_STEPS_FILE="$TMPDIR/steps"
    export FAKE_UPTIME_FILE="$TMPDIR/uptime"
    export FAKE_OTHER_STEPS_FILE="$TMPDIR/other-steps"
    export FAKE_ERROR_FILE="$TMPDIR/errors"

    printf '%s\n' '{"models":{"brain-physical":{"aliases":["tool-calling"]},"other-physical":{"aliases":["coding"]}}}' > "$MLX_WATCHDOG_CONFIG"
    printf 'busy\n' > "$FAKE_MODE_FILE"
    printf 'present\n' > "$FAKE_METRICS_MODE_FILE"
    printf '1000\n' > "$FAKE_NOW_FILE"
    printf '10\n' > "$FAKE_STEPS_FILE"
    printf '100\n' > "$FAKE_UPTIME_FILE"
    printf '100\n' > "$FAKE_OTHER_STEPS_FILE"
    printf '0\n' > "$FAKE_ERROR_FILE"
    bash ${src}/modules/mlx/scripts/mlx-watchdog.sh > "$TMPDIR/first.log" 2>&1
    test "$(<"$MLX_WATCHDOG_BUSY_MARKER")" = 1000

    # A single busy request may run beyond 900 s. Advancing engine steps on
    # the exact brain backend rebase the grace and must not restart it.
    printf '1901\n' > "$FAKE_NOW_FILE"
    printf '11\n' > "$FAKE_STEPS_FILE"
    printf '1001\n' > "$FAKE_UPTIME_FILE"
    bash ${src}/modules/mlx/scripts/mlx-watchdog.sh > "$TMPDIR/progress.log" 2>&1
    test "$(<"$MLX_WATCHDOG_BUSY_MARKER")" = 1901
    test ! -e "$MLX_WATCHDOG_FAIL_MARKER"
    ! grep -q 'kickstart' "$TMPDIR/progress.log"
    grep -q 'engine steps advanced 10->11 -> reset busy grace' "$TMPDIR/progress.log"

    # Other-backend activity and error counters are not brain progress. Frozen
    # brain steps for a full grace interval retain the existing reap rung.
    printf '2802\n' > "$FAKE_NOW_FILE"
    printf '999\n' > "$FAKE_OTHER_STEPS_FILE"
    printf '999\n' > "$FAKE_ERROR_FILE"
    printf '1902\n' > "$FAKE_UPTIME_FILE"
    bash ${src}/modules/mlx/scripts/mlx-watchdog.sh > "$TMPDIR/frozen.log" 2>&1
    test "$(<"$MLX_WATCHDOG_FAIL_MARKER")" = 1
    test ! -e "$MLX_WATCHDOG_BUSY_MARKER"
    test ! -e "$MLX_WATCHDOG_PROGRESS_MARKER"
    grep -q 'no engine progress through 900s grace' "$TMPDIR/frozen.log"

    # Healthy clears failure, busy, and progress state.
    printf 'healthy\n' > "$FAKE_MODE_FILE"
    printf '2900\n' > "$FAKE_NOW_FILE"
    printf '2900\n' > "$MLX_WATCHDOG_BUSY_MARKER"
    printf 'brain-physical\thttp://127.0.0.1:11437\t11\t1902\n' > "$MLX_WATCHDOG_PROGRESS_MARKER"
    bash ${src}/modules/mlx/scripts/mlx-watchdog.sh > "$TMPDIR/healthy.log" 2>&1
    test ! -e "$MLX_WATCHDOG_FAIL_MARKER"
    test ! -e "$MLX_WATCHDOG_BUSY_MARKER"
    test ! -e "$MLX_WATCHDOG_PROGRESS_MARKER"

    # A restarted worker's decreased counter is a new epoch and gets a
    # fresh grace rather than inheriting the old worker's near-expired timer.
    printf 'busy\n' > "$FAKE_MODE_FILE"
    printf '3000\n' > "$MLX_WATCHDOG_BUSY_MARKER"
    printf 'brain-physical\thttp://127.0.0.1:11437\t100\t5\n' > "$MLX_WATCHDOG_PROGRESS_MARKER"
    printf '3901\n' > "$FAKE_NOW_FILE"
    printf '1\n' > "$FAKE_STEPS_FILE"
    printf '10\n' > "$FAKE_UPTIME_FILE"
    bash ${src}/modules/mlx/scripts/mlx-watchdog.sh > "$TMPDIR/counter-reset.log" 2>&1
    test "$(<"$MLX_WATCHDOG_BUSY_MARKER")" = 3901
    test ! -e "$MLX_WATCHDOG_FAIL_MARKER"
    grep -q 'worker epoch reset -> reset busy grace' "$TMPDIR/counter-reset.log"

    # Uptime moving backward independently proves another worker epoch.
    printf '4000\n' > "$MLX_WATCHDOG_BUSY_MARKER"
    printf 'brain-physical\thttp://127.0.0.1:11437\t1\t100\n' > "$MLX_WATCHDOG_PROGRESS_MARKER"
    printf '4901\n' > "$FAKE_NOW_FILE"
    bash ${src}/modules/mlx/scripts/mlx-watchdog.sh > "$TMPDIR/uptime-reset.log" 2>&1
    test "$(<"$MLX_WATCHDOG_BUSY_MARKER")" = 4901
    test ! -e "$MLX_WATCHDOG_FAIL_MARKER"
    grep -q 'worker epoch reset -> reset busy grace' "$TMPDIR/uptime-reset.log"

    # A changed physical/backend identity is also a new worker epoch.
    printf '5000\n' > "$MLX_WATCHDOG_BUSY_MARKER"
    printf 'old-model\thttp://127.0.0.1:11999\t1\t10\n' > "$MLX_WATCHDOG_PROGRESS_MARKER"
    printf '5901\n' > "$FAKE_NOW_FILE"
    bash ${src}/modules/mlx/scripts/mlx-watchdog.sh > "$TMPDIR/identity.log" 2>&1
    test "$(<"$MLX_WATCHDOG_BUSY_MARKER")" = 5901
    test ! -e "$MLX_WATCHDOG_FAIL_MARKER"
    grep -q 'worker identity changed -> reset busy grace' "$TMPDIR/identity.log"

    # Missing metrics are fail-safe: they cannot manufacture progress.
    printf 'missing\n' > "$FAKE_METRICS_MODE_FILE"
    printf '6000\n' > "$MLX_WATCHDOG_BUSY_MARKER"
    printf 'brain-physical\thttp://127.0.0.1:11437\t1\t10\n' > "$MLX_WATCHDOG_PROGRESS_MARKER"
    printf '6901\n' > "$FAKE_NOW_FILE"
    bash ${src}/modules/mlx/scripts/mlx-watchdog.sh > "$TMPDIR/missing.log" 2>&1
    test "$(<"$MLX_WATCHDOG_FAIL_MARKER")" = 1
    grep -q 'no engine progress through 900s grace' "$TMPDIR/missing.log"

    # Ambiguous alias mapping is also fail-safe even with valid metrics.
    printf 'healthy\n' > "$FAKE_MODE_FILE"
    printf '7000\n' > "$FAKE_NOW_FILE"
    bash ${src}/modules/mlx/scripts/mlx-watchdog.sh > /dev/null 2>&1
    printf '%s\n' '{"models":{"brain-physical":{"aliases":["tool-calling"]},"other-physical":{"aliases":["tool-calling"]}}}' > "$MLX_WATCHDOG_CONFIG"
    printf 'busy\n' > "$FAKE_MODE_FILE"
    printf 'present\n' > "$FAKE_METRICS_MODE_FILE"
    printf '7100\n' > "$MLX_WATCHDOG_BUSY_MARKER"
    printf '8001\n' > "$FAKE_NOW_FILE"
    bash ${src}/modules/mlx/scripts/mlx-watchdog.sh > "$TMPDIR/ambiguous.log" 2>&1
    test "$(<"$MLX_WATCHDOG_FAIL_MARKER")" = 1
    grep -q 'no engine progress through 900s grace' "$TMPDIR/ambiguous.log"

    # Dead clears busy/progress state before entering the normal failure rung.
    printf 'healthy\n' > "$FAKE_MODE_FILE"
    printf '8100\n' > "$FAKE_NOW_FILE"
    bash ${src}/modules/mlx/scripts/mlx-watchdog.sh > /dev/null 2>&1
    printf 'dead\n' > "$FAKE_MODE_FILE"
    printf '8200\n' > "$FAKE_NOW_FILE"
    printf '8200\n' > "$MLX_WATCHDOG_BUSY_MARKER"
    printf 'brain-physical\thttp://127.0.0.1:11437\t1\t10\n' > "$MLX_WATCHDOG_PROGRESS_MARKER"
    bash ${src}/modules/mlx/scripts/mlx-watchdog.sh > "$TMPDIR/dead.log" 2>&1
    test ! -e "$MLX_WATCHDOG_BUSY_MARKER"
    test ! -e "$MLX_WATCHDOG_PROGRESS_MARKER"
    test "$(<"$MLX_WATCHDOG_FAIL_MARKER")" = 1

    touch "$out"
  '';
}
