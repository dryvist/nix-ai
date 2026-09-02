#!/usr/bin/env bash
# Report the startup token cost of recent Claude Code sessions, per repository.
#
# The first `usage` block of a session transcript is that session's startup
# cost: system prompt, instruction chain, skill and agent listings, MCP tool
# names, and the first user turn. Reading it needs no telemetry, no collector
# and no running service — the transcripts are already on disk.
#
# Usage:
#   agent-context-baseline                # every project, last 24h
#   agent-context-baseline --hours 72     # widen the window
#   agent-context-baseline --repo nix-ai  # substring match on the project dir
#   agent-context-baseline --budget 90000 # override the pass/fail threshold
#
# Exits 1 when the newest session of any reported repo is over budget, so it
# can gate a check rather than only inform.
set -euo pipefail

hours=24
budget=90000
repo=

while [ $# -gt 0 ]; do
  case "$1" in
    --hours) hours=${2:?--hours needs a value}; shift 2 ;;
    --budget) budget=${2:?--budget needs a value}; shift 2 ;;
    --repo) repo=${2:?--repo needs a value}; shift 2 ;;
    -h | --help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "agent-context-baseline: unknown argument: $1" >&2; exit 2 ;;
  esac
done

projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
[ -d "$projects" ] || {
  echo "agent-context-baseline: no transcripts at $projects" >&2
  exit 1
}

HOURS="$hours" BUDGET="$budget" REPO="$repo" PROJECTS="$projects" python3 - <<'PY'
import glob
import json
import os
import time

projects = os.environ["PROJECTS"]
hours = float(os.environ["HOURS"])
budget = int(os.environ["BUDGET"])
repo_filter = os.environ["REPO"]
cutoff = time.time() - hours * 3600

# Newest session wins per repo: a cut only takes effect for sessions started
# after it, so an older transcript says nothing about the current config.
newest: dict[str, tuple[float, int, str]] = {}
counted = 0

for path in glob.glob(os.path.join(projects, "*", "*.jsonl")):
    mtime = os.path.getmtime(path)
    if mtime < cutoff:
        continue
    project = os.path.basename(os.path.dirname(path))
    if repo_filter and repo_filter not in project:
        continue
    first = None
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for index, line in enumerate(handle):
                if index > 200:
                    break
                if '"usage"' not in line:
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                usage = (record.get("message") or {}).get("usage") or {}
                total = (
                    usage.get("input_tokens", 0)
                    + usage.get("cache_read_input_tokens", 0)
                    + usage.get("cache_creation_input_tokens", 0)
                )
                # Below this a record is a continuation, not a session start.
                if total > 1000:
                    first = total
                    break
    except OSError:
        continue
    if first is None:
        continue
    counted += 1
    if project not in newest or mtime > newest[project][0]:
        newest[project] = (mtime, first, os.path.basename(path)[:8])

if not newest:
    print(f"no sessions with a usage block in the last {hours:g}h")
    raise SystemExit(0)

print(f"{'newest session':16} {'first request':>13}  {'vs budget':>9}  repo")
over = 0
for project, (mtime, first, _sid) in sorted(
    newest.items(), key=lambda item: -item[1][1]
):
    delta = first - budget
    flag = f"+{delta:,}" if delta > 0 else f"{delta:,}"
    if delta > 0:
        over += 1
    # Project dirs encode the cwd with "/" replaced by "-", which is not
    # reversible (repo names contain dashes too). Strip the home prefix and
    # leave the rest as the encoded form rather than guessing separators.
    label = project.lstrip("-")
    for prefix in ("Users-jevans-git-", "Users-jevans-"):
        if label.startswith(prefix):
            label = label[len(prefix):] or "~"
            break
    print(
        f"{time.strftime('%m-%d %H:%M', time.localtime(mtime)):16}"
        f" {first:13,}  {flag:>9}  {label}"
    )

print(
    f"\n{len(newest)} repo(s) from {counted} session(s), "
    f"budget {budget:,}, {over} over"
)
raise SystemExit(1 if over else 0)
PY
