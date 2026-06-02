#!/usr/bin/env bash
# Periodic watchdog — kicks the vllm-mlx LaunchAgent when worker memory pressure
# or stuck-past-TTL conditions cross thresholds. Defensive layer against the
# upstream mostlygeek/llama-swap lifecycle race at proxy/process.go:280-289
# (`panic: sync: WaitGroup is reused before previous Wait has returned`).
# See nix-ai#801 + docs-starlight/d/hosts/local-llm-stack.
#
# Usage: mlx-watchdog (intended to run via LaunchAgent StartInterval).
#
# Tunable env vars (all optional, with sane defaults for an M4 Max 128 GB host):
#   MLX_LAUNCHD_LABEL          launchd label of the LaunchAgent to kick
#   MLX_WATCHDOG_LOG           log file path
#   MLX_WATCHDOG_CONFIG        path to llama-swap.json (TTL lookup)
#   MLX_WATCHDOG_SWAP_PCT      swap usage % threshold (default 75)
#   MLX_WATCHDOG_RSS_PCT       single-worker RSS % of physical RAM (default 50)
#   MLX_WATCHDOG_TTL_MULT      etime / configured-ttl multiplier (default 2)

set -euo pipefail

label="${MLX_LAUNCHD_LABEL:?MLX_LAUNCHD_LABEL must be set}"
log="${MLX_WATCHDOG_LOG:-$HOME/Library/Logs/vllm-mlx/watchdog.log}"
cfg="${MLX_WATCHDOG_CONFIG:-$HOME/.config/mlx/llama-swap.json}"
swap_pct_max="${MLX_WATCHDOG_SWAP_PCT:-75}"
rss_pct_max="${MLX_WATCHDOG_RSS_PCT:-50}"
ttl_mult="${MLX_WATCHDOG_TTL_MULT:-2}"

mkdir -p "$(dirname "$log")"
ts() { date +%Y-%m-%dT%H:%M:%S; }
note() { printf '%s %s\n' "$(ts)" "$*" >> "$log"; }

trigger=""

# Worker enumeration (one line per worker: pid etime model)
workers=$(
  ps -axww -o pid,etime,command \
    | awk '/bin\/python.*bin\/vllm-mlx serve/ {
        model = "unknown";
        for (i = 3; i <= NF; i++) {
          if ($i == "serve" && (i + 1) <= NF) { model = $(i + 1); break }
        }
        print $1, $2, model
      }'
)

if [ -z "$workers" ]; then
  note "OK no workers running"
  exit 0
fi

# 1. Stuck-past-TTL check — etime greater than ttl_mult * configured ttl.
while IFS= read -r row; do
  pid=$(awk '{print $1}' <<< "$row")
  etime=$(awk '{print $2}' <<< "$row")
  model=$(awk '{print $3}' <<< "$row")
  [ -z "$model" ] || [ "$model" = "unknown" ] && continue

  ttl=$(jq -r --arg m "$model" '.models[$m].ttl // 0' "$cfg" 2>/dev/null || echo 0)
  [ "${ttl:-0}" = "0" ] && continue

  secs=$(awk -v e="$etime" 'BEGIN {
    n = split(e, a, /[-:]/);
    if      (n == 4) print (a[1]*86400) + (a[2]*3600) + (a[3]*60) + a[4];
    else if (n == 3) print (a[1]*3600) + (a[2]*60) + a[3];
    else if (n == 2) print (a[1]*60) + a[2];
    else             print 0;
  }')

  threshold=$(( ttl * ttl_mult ))
  if [ "$secs" -gt "$threshold" ]; then
    trigger="STUCK_WORKER pid=$pid model=$model etime=${secs}s ttl=${ttl}s ratio=$(awk -v s="$secs" -v t="$ttl" 'BEGIN{printf "%.1f", s/t}')x"
    break
  fi
done <<< "$workers"

# 2. Swap pressure check.
if [ -z "$trigger" ]; then
  read -r swap_total swap_used < <(
    sysctl -n vm.swapusage | awk '{
      for (i = 1; i <= NF; i++) {
        if ($i == "total") { t = $(i + 2); sub(/[A-Za-z]+$/, "", t) }
        if ($i == "used")  { u = $(i + 2); sub(/[A-Za-z]+$/, "", u) }
      }
      print t, u
    }'
  )
  if [ -n "${swap_total:-}" ] && [ -n "${swap_used:-}" ]; then
    swap_pct=$(awk -v u="$swap_used" -v t="$swap_total" 'BEGIN { printf "%d", (t > 0) ? u * 100 / t : 0 }')
    if [ "$swap_pct" -gt "$swap_pct_max" ]; then
      trigger="SWAP_PRESSURE swap_used=${swap_used}MB swap_total=${swap_total}MB pct=${swap_pct}%"
    fi
  fi
fi

# 3. Single-worker RSS > rss_pct_max % of physical RAM.
if [ -z "$trigger" ]; then
  phys_mb=$(( $(sysctl -n hw.memsize) / 1048576 ))
  rss_threshold_mb=$(( phys_mb * rss_pct_max / 100 ))
  while IFS= read -r tline; do
    pid=$(awk '{print $1}' <<< "$tline")
    rss_raw=$(awk '{print $2}' <<< "$tline")
    rss_mb=$(awk -v r="$rss_raw" 'BEGIN {
      v = r + 0;
      if (r ~ /G$/) v *= 1024;
      else if (r ~ /K$/) v /= 1024;
      else if (r ~ /T$/) v *= 1048576;
      printf "%d", v;
    }')
    if [ "$rss_mb" -gt "$rss_threshold_mb" ]; then
      trigger="RSS_PRESSURE pid=$pid rss_mb=$rss_mb threshold_mb=$rss_threshold_mb (${rss_pct_max}% of ${phys_mb}MB)"
      break
    fi
  done < <(top -l 1 -o rsize -n 10 -stats pid,rsize,command \
             | awk '/bin\/python.*bin\/vllm-mlx serve/ {print $1, $2}')
fi

if [ -z "$trigger" ]; then
  note "OK no triggers"
  exit 0
fi

note "TRIGGER $trigger"
note "ACTION launchctl kickstart -k gui/$(id -u)/$label"
launchctl kickstart -k "gui/$(id -u)/$label" 2>&1 | sed 's/^/  /' >> "$log" || true
note "DONE"
exit 1
