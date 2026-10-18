{ pkgs, instructions }:

pkgs.runCommand "shared-agent-instructions" { } ''
  set -e
  operating_core="${instructions.pkg}/agentsmd/rules/operating-core.md"
  rule_count=$(grep -Fc 'Check system state with monitoring first;' "$operating_core" || true)
  if [ "$rule_count" -ne 1 ]; then
    echo "expected exactly one monitoring-first line in operating-core.md, found $rule_count" >&2
    exit 1
  fi
  cat "${instructions.pkg}/AGENTS.md" > "$out"
  printf '\n' >> "$out"
  grep -F 'Check system state with monitoring first;' "$operating_core" >> "$out"
''
