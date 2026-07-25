# shellcheck shell=bash
# Fake curl for the alert() Slack contract test (alert-payload-test.sh).
# Records the JSON body into $FAKE_PAYLOAD_FILE and replays "<body>\n<code>"
# exactly as `curl -w '\n%{http_code}'` does, with the code from $FAKE_CODE_FILE.
while (($# > 0)); do
  case "$1" in
    --data-binary)
      printf '%s' "$2" > "$FAKE_PAYLOAD_FILE"
      shift 2
      ;;
    -w | -H | -m | -X) shift 2 ;;
    *) shift ;;
  esac
done
printf 'slack-said-no\n%s' "$(<"$FAKE_CODE_FILE")"
