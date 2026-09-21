#!/usr/bin/env bash
set -euo pipefail

aliases_source=$1
claude_zai_bin=$2
test_root=$(mktemp -d)
mkdir -p "$test_root/bin"

cat > "$test_root/bin/doppler" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$DOPPLER_LOG"
while [ "$1" != "--" ]; do shift; done
shift
export ZAI_SUBSCRIPTION_KEY=test-secret
exec "$@"
EOF
chmod +x "$test_root/bin/doppler"

cat > "$test_root/bin/claude" <<'EOF'
#!/bin/sh
env | grep -E '^(ANTHROPIC_|CLAUDE_CODE_|API_TIMEOUT_MS|OPENAI_API_KEY)' | sort > "$CLAUDE_ENV_LOG"
printf '%s\n' "$@" > "$CLAUDE_ARGS_LOG"
exit 23
EOF
chmod +x "$test_root/bin/claude"

cat > "$test_root/bin/codex" <<'EOF'
#!/bin/sh
env | grep -E '^(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|ZAI_SUBSCRIPTION_KEY)' | sort > "$CODEX_ENV_LOG"
printf '%s\n' "$@" > "$CODEX_ARGS_LOG"
exit 24
EOF
chmod +x "$test_root/bin/codex"

export PATH="$test_root/bin:$PATH"
export ZAI_DOPPLER_PROJECT=gh-workflow-tokens
export ZAI_DOPPLER_CONFIG=dryvist
export ZAI_DOPPLER_KEY_ENV=ZAI_SUBSCRIPTION_KEY
export ZAI_CLAUDE_BASE_URL=https://api.z.ai/api/anthropic
export ZAI_CLAUDE_PRIMARY_MODEL='glm-5.3[1m]'
export ZAI_CLAUDE_FAST_MODEL='glm-5.3-flash[1m]'
export ZAI_CLAUDE_AUTO_COMPACT_WINDOW=500000
export ANTHROPIC_API_KEY=ambient-anthropic-key
export ANTHROPIC_AUTH_TOKEN=ambient-anthropic-token
export CLAUDE_CODE_OAUTH_TOKEN=ambient-claude-oauth-token
export CLAUDE_CODE_USE_BEDROCK=1
export CLAUDE_CODE_USE_VERTEX=1
export OPENAI_API_KEY=ambient-openai-key
export DOPPLER_LOG="$test_root/doppler.log"
export CLAUDE_ENV_LOG="$test_root/claude-env.log"
export CLAUDE_ARGS_LOG="$test_root/claude-args.log"
export CODEX_ARGS_LOG="$test_root/codex-args.log"
export CODEX_ENV_LOG="$test_root/codex-env.log"

set +e
"$claude_zai_bin" "two words" --flag
claude_rc=$?
set -e
[ "$claude_rc" -eq 23 ]
diff -u <(printf '%s\n' run -p gh-workflow-tokens -c dryvist --no-fallback --only-secrets ZAI_SUBSCRIPTION_KEY -- "$claude_zai_bin" 'two words' --flag) "$DOPPLER_LOG"
diff -u <(printf '%s\n' 'two words' --flag) "$CLAUDE_ARGS_LOG"
grep -Fxq 'ANTHROPIC_API_KEY=' "$CLAUDE_ENV_LOG"
grep -Fxq 'ANTHROPIC_AUTH_TOKEN=test-secret' "$CLAUDE_ENV_LOG"
grep -Fxq 'ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic' "$CLAUDE_ENV_LOG"
grep -Fxq 'ANTHROPIC_CUSTOM_HEADERS=' "$CLAUDE_ENV_LOG"
grep -Fxq 'CLAUDE_CODE_OAUTH_TOKEN=' "$CLAUDE_ENV_LOG"
grep -Fxq 'CLAUDE_CODE_USE_BEDROCK=' "$CLAUDE_ENV_LOG"
grep -Fxq 'CLAUDE_CODE_USE_VERTEX=' "$CLAUDE_ENV_LOG"
grep -Fxq 'OPENAI_API_KEY=' "$CLAUDE_ENV_LOG"
grep -Fxq 'ANTHROPIC_DEFAULT_FABLE_MODEL=glm-5.3[1m]' "$CLAUDE_ENV_LOG"
grep -Fxq 'ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.3[1m]' "$CLAUDE_ENV_LOG"
grep -Fxq 'ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.3-flash[1m]' "$CLAUDE_ENV_LOG"
grep -Fxq 'ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5.3-flash[1m]' "$CLAUDE_ENV_LOG"
grep -Fxq 'CLAUDE_CODE_SUBAGENT_MODEL=glm-5.3-flash[1m]' "$CLAUDE_ENV_LOG"
grep -Fxq 'CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000' "$CLAUDE_ENV_LOG"
grep -Fxq 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1' "$CLAUDE_ENV_LOG"
grep -Fxq 'API_TIMEOUT_MS=3000000' "$CLAUDE_ENV_LOG"

set +e
zsh -c 'source "$1"; codex-zai "two words" --flag' zsh "$aliases_source"
codex_rc=$?
set -e
[ "$codex_rc" -eq 24 ]
diff -u <(printf '%s\n' run -p gh-workflow-tokens -c dryvist --no-fallback --only-secrets ZAI_SUBSCRIPTION_KEY -- zsh -c) <(head -n 11 "$DOPPLER_LOG")
diff -u <(printf '%s\n' --profile zai 'two words' --flag) "$CODEX_ARGS_LOG"
grep -Fxq 'ANTHROPIC_API_KEY=' "$CODEX_ENV_LOG"
grep -Fxq 'ANTHROPIC_AUTH_TOKEN=' "$CODEX_ENV_LOG"
grep -Fxq 'OPENAI_API_KEY=' "$CODEX_ENV_LOG"
grep -Fxq 'ZAI_SUBSCRIPTION_KEY=test-secret' "$CODEX_ENV_LOG"
