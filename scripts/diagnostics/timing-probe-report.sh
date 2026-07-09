#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
export LANG=C

input="${1:-10}"
out="${2:-.meta/timing-probe-$(date +%Y%m%d-%H%M%S).log}"
threshold="${TIMING_PROBE_LATE_MS:-2}"
failure_threshold="${TIMING_PROBE_FAILURE_MS:-5}"

if [[ -f "$input" ]]; then
  out="$input"
  printf 'analyzing %s\n' "$out"
elif [[ "$input" =~ ^[0-9]+[mhd]?$ ]]; then
  window="$input"
  if [[ "$window" =~ ^[0-9]+$ ]]; then
    window="${window}m"
  fi
  mkdir -p "$(dirname "$out")"
  /usr/bin/log show --info --last "$window" --style compact \
    --predicate 'subsystem == "ai.sequencer.SequencerAI.activity" AND category == "timing-probe"' \
    > "$out"
  printf 'wrote %s\n' "$out"
else
  printf 'usage: %s [minutes|window|saved-log-file] [output-log]\n' "$0" >&2
  printf 'examples: %s 10m .meta/timing.log | %s .meta/timing.log\n' "$0" "$0" >&2
  exit 64
fi
printf '\n== View / activity breadcrumbs ==\n'
grep -E 'view-switch|activity name=workspace-mode' "$out" || true

printf '\n== Late events >= %sms ==\n' "$threshold"
TIMING_PROBE_LATE_MS="$threshold" perl -ne '
  if (/lateMs=([-0-9.]+)/ && $1 >= $ENV{TIMING_PROBE_LATE_MS}) {
    print "$1\t$_";
  }
' "$out" | sort -nr | head -50 || true

printf '\n== Slow process ticks >= %sms ==\n' "$threshold"
TIMING_PROBE_LATE_MS="$threshold" perl -ne '
  if (/durationMs=([-0-9.]+)/ && $1 >= $ENV{TIMING_PROBE_LATE_MS}) {
    print "$1\t$_";
  }
' "$out" | sort -nr | head -50 || true

printf '\n== Cache misses ==\n'
grep -E 'sample-cache phase=lookup .* result=(miss|missing|loading|failed|stale)|sample-cache phase=load .* result=failed|sample-cache phase=evict' "$out" || true

printf '\n== Main-hop waits >= %sms ==\n' "$threshold"
TIMING_PROBE_LATE_MS="$threshold" perl -ne '
  if (/sample-main-hop .* waitMs=([-0-9.]+)/ && $1 >= $ENV{TIMING_PROBE_LATE_MS}) {
    print "$1\t$_";
  }
' "$out" | sort -nr | head -50 || true

printf '\n== Graph repairs / reconnects ==\n'
perl -ne '
  if (/graph-repair .* durationMs=([-0-9.]+)/) {
    print "$1\t$_";
  }
' "$out" | sort -nr | head -50 || true

printf '\n== Cache warmup durations ==\n'
perl -ne '
  if (/sample-cache phase=load .* durationMs=([-0-9.]+)/) {
    print "$1\t$_";
  }
' "$out" | sort -nr | head -50 || true

printf '\n== Timing Summary ==\n'
script_dir="$(cd "$(dirname "$0")" && pwd)"
TIMING_PROBE_LATE_MS="$threshold" TIMING_PROBE_FAILURE_MS="$failure_threshold" \
  perl "$script_dir/timing-probe-summary.pl" "$out"
