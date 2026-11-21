# Fake curl for the claude-router-launchers check: serves fixed router model discovery responses.
{ pkgs }:
pkgs.writeShellScriptBin "curl" ''
  set -euo pipefail
  output=
  authorization=
  url=
  while (($#)); do
    case "$1" in
      --output)
        output=$2
        shift
        ;;
      --header)
        if [[ "$2" == @- ]]; then
          IFS= read -r authorization
        else
          authorization=$2
        fi
        shift
        ;;
      --write-out)
        shift
        ;;
      */*)
        url=$1
        ;;
    esac
    shift
  done

  test "$authorization" = "Authorization: Bearer $EXPECTED_AUTH_TOKEN"
  test -n "$output"
  case "$url" in
    "$EXPECTED_API_ROOT/models")
      cat >"$output" <<'JSON'
  {"data":[{"id":"medium"},{"id":"small"},{"id":"wide"},{"id":"image-only"}]}
  JSON
      ;;
    "$EXPECTED_API_ROOT/models?include_metadata=true&fallback_type=context_window")
      cat >"$output" <<'JSON'
  {"data":[
    {"id":"medium","metadata":{"fallbacks":["wide"]}},
    {"id":"small","metadata":{"fallbacks":[]}},
    {"id":"wide","metadata":{"fallbacks":[]}}
  ]}
  JSON
      ;;
    "''${EXPECTED_API_ROOT%/v1}/model/info")
      cat >"$output" <<'JSON'
  {"data":[
    {"model_name":"medium","model_info":{"max_input_tokens":64000}},
    {"model_name":"medium","model_info":{"max_input_tokens":120000}},
    {"model_name":"small","model_info":{"max_input_tokens":24000}},
    {"model_name":"small","model_info":{"max_input_tokens":32000}},
    {"model_name":"wide","model_info":{"max_input_tokens":200000}}
  ]}
  JSON
      ;;
    *)
      printf 'unexpected model discovery URL: %s\n' "$url" >&2
      exit 1
      ;;
  esac
  printf '200'
''
