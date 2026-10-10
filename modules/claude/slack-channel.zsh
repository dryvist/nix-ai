# Slack channel opt-in for interactive Claude Code sessions.
#
# Sourced only when programs.claude.slackChannel.enable is set (claude-config.nix).
# A session opts in with CLAUDE_SLACK_CHANNEL=1 and SLACK_OPERATOR_USER_ID set to
# the operator's Slack member ID. Anything else runs the plain `claude` binary.
#
# The bot and app tokens come from OpenBao through openbao-run and reach only the
# child process environment. The one file written is a per-session access.json
# holding the operator ID (never a token); it lives in a mktemp directory that is
# removed when claude exits. The secret item is seeded by the operator at
# secrets-external/ai/claude-slack with fields SLACK_BOT_TOKEN and SLACK_APP_TOKEN.

claude() {
  local arg bin state_dir rc
  if [[ "${CLAUDE_SLACK_CHANNEL:-}" != 1 ]] || [[ ! -t 0 || ! -t 1 ]]; then
    command claude "$@"
    return
  fi
  for arg in "$@"; do
    case "$arg" in
      -p | --print) command claude "$@"; return ;;
    esac
  done
  if [[ ! "${SLACK_OPERATOR_USER_ID:-}" =~ ^[UW][A-Z0-9]+$ ]]; then
    print -u2 "claude: CLAUDE_SLACK_CHANNEL=1 needs SLACK_OPERATOR_USER_ID set to a Slack member ID; starting without the Slack channel"
    command claude "$@"
    return
  fi
  bin="$(whence -p claude)" || { print -u2 "claude: binary not found on PATH"; return 1; }
  state_dir="$(mktemp -d)" || return 1
  chmod 700 "$state_dir"
  printf '{"dmPolicy":"allowlist","allowFrom":["%s"],"groups":{}}\n' "$SLACK_OPERATOR_USER_ID" \
    > "$state_dir/access.json"
  SLACK_STATE_DIR="$state_dir" SLACK_ACCESS_MODE=static \
    openbao-run \
      --secret secrets-external:SLACK_BOT_TOKEN=ai/claude-slack#SLACK_BOT_TOKEN \
      --secret secrets-external:SLACK_APP_TOKEN=ai/claude-slack#SLACK_APP_TOKEN \
      -- "$bin" --dangerously-load-development-channels plugin:slack@claude-channel-slack "$@"
  rc=$?
  rm -rf "$state_dir"
  return $rc
}
