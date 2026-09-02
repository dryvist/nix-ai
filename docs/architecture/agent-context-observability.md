# Agent context observability

Every failure in the 2026-09-02 stable-links session was a number nobody was
watching. This is the collector that makes each one a threshold instead of a
discovery.

`modules/scripts/agent-context-metrics.sh` emits newline-delimited JSON, one
object per metric. Health metrics make **no model calls** and run in about a
second, so they belong on a short timer. Token measurement starts real
sessions and is opt-in behind `--with-tokens`.

## What each metric would have caught

| Metric | The failure it makes visible |
| --- | --- |
| `skills_reachable{harness}` | A group cut took `~/.agents/skills` from 72 entries to 11, removing 121 skills carrying 164,619 recorded invocations. Nothing reported it; it surfaced when a person tried to run one. |
| `skills_in_catalog` | The denominator. `skills_reachable` alone cannot distinguish "small catalogue" from "catalogue collapsed". |
| `plugins_missing` | A cache purge left 113 of 115 plugins with a missing `installPath`. Every session that had resolved those paths at startup was broken, silently, until a manual plugin reload. |
| `links_via_aggregate{tree}` | `home.file` routes every managed path through one derivation whose hash covers the entire home configuration, so every link moved on every rebuild regardless of content. Invisible without diffing `readlink` across generations. |
| `root_via_aggregate{root}` | A harness *root* that is itself an aggregate symlink churns even when the tree behind it is stable. This is the shape the qwen and antigravity roots still have, and it was missed by a review that only checked the trees. |
| `session_tokens{repo}` | A repo's startup cost doubled between two days with no single obvious cause. |

## Alerts worth having

Thresholds, not trends — each of these is a step change, not a drift:

```text
skills_reachable{harness!="claude"} < skills_in_catalog * 0.5     → page
plugins_missing > 0                                              → page
links_via_aggregate > 0                                          → warn
root_via_aggregate > 0                                           → warn
session_tokens{repo} > 90000                                     → warn
```

`skills_reachable` is deliberately compared against the catalogue rather than
a constant: the catalogue grows, and a fixed floor would rot into a
false-negative.

Claude is excluded from the first alert because it does not read
`~/.agents/skills` at all — it reads `~/.claude/skills`, its enabled plugins,
and `<repo>/.claude/skills`. Its reachability is covered by `plugins_missing`.

## What is already native — do not rebuild it

Claude Code exports OpenTelemetry natively, and this estate already has it on:
`CLAUDE_CODE_ENABLE_TELEMETRY=1` with OTLP metrics going to VictoriaMetrics,
plus `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`.

Native metrics cover **usage and cost**: tokens, sessions, active coding time,
lines of code, commits, PRs, tool decisions, cache hit ratio, per-model and
per-session breakdowns. Community dashboards consume them directly:

| Dashboard | Covers |
| --- | --- |
| [Grafana #25255 — Claude Code Metrics (Prometheus)](https://grafana.com/grafana/dashboards/25255-claude-code-metrics-prometheus/) | cost, tokens, sessions, active time, LOC, commits, PRs, tool decisions, cache hit ratio, leaderboards. Works against Prometheus, VictoriaMetrics, Mimir, Thanos. |
| [Grafana #25052 — Claude Code](https://grafana.com/grafana/dashboards/25052-claude-code/) | cost, API requests, tool usage, code-edit acceptance rate, per-user breakdown, error detail |

Source for #25255: <https://github.com/rockdarko/claude-code-metrics-prometheus>

**`session_tokens` in this collector duplicates native telemetry and should be
treated as a fallback**, for a host where OTEL is off or a one-off comparison.
Prefer the native metric.

**What native telemetry does NOT measure is configuration health.** No native
metric and no community dashboard would have shown `skills_reachable`
collapsing from 132 to 11, `plugins_missing` reaching 113 of 115, or links
churning through the aggregate on every rebuild. Those are precisely the
failures this collector exists for, and they are invisible to every dashboard
above. That is the whole justification for it — anything native already covers
belongs in the native pipeline instead.

## Shipping it

Send it to the **same** backend the native metrics already reach, so one
dashboard shows usage and health together. VictoriaMetrics accepts Prometheus
line protocol directly:

```sh
agent-context-metrics.sh |
  python3 -c '
import json,sys
for line in sys.stdin:
    d=json.loads(line)
    labels=",".join(f"{k}=\"{v}\"" for k,v in d.items()
                    if k not in ("time","metric","value"))
    print(f"agent_context_{d[\"metric\"]}{{{labels}}} {d[\"value\"]}")
' |
  curl -s --data-binary @- \
    "http://$VM_HOST:8428/api/v1/import/prometheus"
```

If a Splunk copy is wanted as well, each line is already a valid HEC `event`
payload body; the token comes from the runtime secret store at call time, never
from a file and never from `.envrc`.

```sh
agent-context-metrics.sh |
  while IFS= read -r line; do
    printf '{"event":%s,"sourcetype":"agent_context"}\n' "$line"
  done |
  curl -s -H "Authorization: Splunk $HEC_TOKEN" \
       --data-binary @- "https://$SPLUNK_HOST:8088/services/collector"
```

The token comes from the runtime secret store at call time, never from a file
and never from `.envrc`.

For Grafana instead, write the same values to a Prometheus textfile-exporter
`.prom` file; the metric names are already label-shaped.

## Cadence

- **Health metrics**: every few minutes, and unconditionally on activation.
  They are cheap and the failures they catch are step changes that otherwise
  persist until a person trips over them.
- **`--with-tokens`**: hourly at most. It starts a real session per repo.

Running the health metrics **as the last step of activation** is the highest
value placement: every failure this collector was built for was introduced by a
rebuild, so the check belongs where the rebuild ends.

## The measurement trap

`session_tokens` uses `--strict-mcp-config`. Without it, a bare `claude -p`
attaches claude.ai hosted MCP connectors that connect nondeterministically and
swing the total by up to 25k with **no config change at all** — two runs twenty
minutes apart differed by ~16k. Absolute values still drift within a session;
only differences measured in a short window are trustworthy.
