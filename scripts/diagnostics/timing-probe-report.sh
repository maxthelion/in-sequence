#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
export LANG=C

input="${1:-10}"
out="${2:-.meta/timing-probe-$(date +%Y%m%d-%H%M%S).log}"
threshold="${TIMING_PROBE_LATE_MS:-2}"
failure_threshold="${TIMING_PROBE_FAILURE_MS:-5}"

mkdir -p "$(dirname "$out")"

if [[ -f "$input" ]]; then
  out="$input"
  printf 'analyzing %s\n' "$out"
elif [[ "$input" =~ ^[0-9]+[mhd]?$ ]]; then
  window="$input"
  if [[ "$window" =~ ^[0-9]+$ ]]; then
    window="${window}m"
  fi
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
TIMING_PROBE_LATE_MS="$threshold" TIMING_PROBE_FAILURE_MS="$failure_threshold" perl - "$out" <<'PERL'
use strict;
use warnings;

my $path = shift @ARGV;
my $warning_ms = $ENV{TIMING_PROBE_LATE_MS} + 0;
my $failure_ms = $ENV{TIMING_PROBE_FAILURE_MS} + 0;
my @markers;
my (%late_by_kind, %main_by_reason, %graph_by_cause, %cache_by_result, %cache_by_sample_track, %correlation);
my (%failure_by_kind, %cache_problem_by_key, %main_problem_by_reason, %graph_problem_by_cause, %uncorrelated_late_by_kind);
my $failure_count = 0;

sub p95 {
    my @values = sort { $a <=> $b } @_;
    return 0 unless @values;
    my $index = int((@values - 1) * 0.95 + 0.5);
    return $values[$index];
}

sub max_value {
    my @values = @_;
    return 0 unless @values;
    my $max = $values[0];
    for my $value (@values) {
        $max = $value if $value > $max;
    }
    return $max;
}

open my $fh, "<", $path or die "open $path: $!";
while (my $line = <$fh>) {
    my ($time) = $line =~ /t=([0-9.]+)/;
    if ($line =~ /view-switch|activity name=/) {
        push @markers, { time => $time // -1, type => "view/activity" };
    }
    if ($line =~ /sample-cache phase=lookup .* result=([^ ]+)/) {
        my $result = $1;
        $cache_by_result{$result}++;
        my ($sample) = $line =~ /(?:sample|sampleID)=([^ ]+)/;
        my ($track) = $line =~ /(?:track|trackID)=([^ ]+)/;
        my $sample_key = $sample // "unknown-sample";
        my $track_key = $track // "unknown-track";
        my $cache_key = "$result sample=$sample_key track=$track_key";
        $cache_by_sample_track{$cache_key}++;
        if ($result ne "hit") {
            $cache_problem_by_key{"sample=$sample_key track=$track_key result=$result"}++;
            push @markers, { time => $time // -1, type => "cache-$result" };
        }
    }
    if ($line =~ /sample-cache phase=load .* result=failed/) {
        $cache_by_result{load_failed}++;
        my ($sample) = $line =~ /(?:sample|sampleID)=([^ ]+)/;
        $cache_problem_by_key{"sample=" . ($sample // "unknown-sample") . " result=load_failed"}++;
        push @markers, { time => $time // -1, type => "cache-failed" };
    }
    if ($line =~ /sample-cache phase=evict/) {
        $cache_by_result{evict}++;
        my ($sample) = $line =~ /(?:sample|sampleID)=([^ ]+)/;
        $cache_problem_by_key{"sample=" . ($sample // "unknown-sample") . " result=evict"}++;
        push @markers, { time => $time // -1, type => "cache-evict" };
    }
    if ($line =~ /sample-main-hop .* reason=([^ ]+)/) {
        my $reason = $1;
        push @markers, { time => $time // -1, type => "main-hop-$reason" };
    }
    if ($line =~ /sample-main-hop / && $line =~ /waitMs=([-0-9.]+)/ && $line =~ /reason=([^ ]+)/) {
        my ($wait) = $line =~ /waitMs=([-0-9.]+)/;
        my ($reason) = $line =~ /reason=([^ ]+)/;
        push @{ $main_by_reason{$reason} }, $wait + 0;
        $main_problem_by_reason{$reason}++ if ($wait + 0) >= $warning_ms;
    }
    if ($line =~ /graph-repair / && $line =~ /durationMs=([-0-9.]+)/) {
        my ($duration) = $line =~ /durationMs=([-0-9.]+)/;
        my ($subsystem) = $line =~ /subsystem=([^ ]+)/;
        my ($cause) = $line =~ /cause=([^ ]+)/;
        my $key = join("/", grep { defined && length } ($subsystem, $cause));
        $key = "unknown" if $key eq "";
        push @{ $graph_by_cause{$key} }, $duration + 0;
        $graph_problem_by_cause{$key}++;
        push @markers, { time => $time // -1, type => "graph-repair-$key" };
    }
    if ($line =~ /event-dispatch kind=([^ ]+).*lateMs=([-0-9.]+)/) {
        my ($kind, $late) = ($1, $2 + 0);
        push @{ $late_by_kind{$kind} }, $late;
        if ($late >= $failure_ms) {
            $failure_count++;
            $failure_by_kind{$kind}++;
        }
        next if $late < $warning_ms;
        my %near;
        for my $marker (@markers) {
            next if !defined $time || $marker->{time} < 0;
            my $delta = ($time + 0) - $marker->{time};
            next if $delta < 0 || $delta > 2.0;
            $near{$marker->{type}} = 1;
        }
        if (!%near) {
            $correlation{"late event with no nearby marker"}++;
            $uncorrelated_late_by_kind{$kind}++;
        } else {
            for my $type (keys %near) {
                $correlation{"late event preceded by $type"}++;
            }
        }
    }
}

print "Late event by kind (count p95_ms max_ms)\n";
for my $kind (sort keys %late_by_kind) {
    my @values = @{ $late_by_kind{$kind} };
    printf "%s %d %.3f %.3f\n", $kind, scalar(@values), p95(@values), max_value(@values);
}

print "\nMain-hop wait by reason (count p95_ms max_ms)\n";
for my $reason (sort keys %main_by_reason) {
    my @values = @{ $main_by_reason{$reason} };
    printf "%s %d %.3f %.3f\n", $reason, scalar(@values), p95(@values), max_value(@values);
}

print "\nGraph repair/reconnect by cause (count p95_ms max_ms)\n";
for my $cause (sort keys %graph_by_cause) {
    my @values = @{ $graph_by_cause{$cause} };
    printf "%s %d %.3f %.3f\n", $cause, scalar(@values), p95(@values), max_value(@values);
}

print "\nCache lookup/load summary\n";
for my $result (sort keys %cache_by_result) {
    print "$result $cache_by_result{$result}\n";
}

print "\nCache lookup by sample/track (result sample track count)\n";
for my $key (sort keys %cache_by_sample_track) {
    print "$key $cache_by_sample_track{$key}\n";
}

print "\nLate-event correlation groups (warning threshold ${warning_ms}ms, 2s lookback)\n";
for my $key (sort keys %correlation) {
    print "$key $correlation{$key}\n";
}

my @suggestions;
for my $kind (sort keys %failure_by_kind) {
    push @suggestions, [
        $failure_by_kind{$kind},
        "event lateness",
        "Investigate $kind dispatch scheduling; $failure_by_kind{$kind} event(s) exceeded ${failure_ms}ms."
    ];
}
for my $key (sort keys %cache_problem_by_key) {
    push @suggestions, [
        $cache_problem_by_key{$key},
        "cache readiness",
        "Warm or pin cache entry $key before transport; $cache_problem_by_key{$key} lookup/load problem(s)."
    ];
}
for my $reason (sort keys %main_problem_by_reason) {
    push @suggestions, [
        $main_problem_by_reason{$reason},
        "main-hop wait",
        "Remove or bound realtime-adjacent main hop reason=$reason; $main_problem_by_reason{$reason} wait(s) exceeded ${warning_ms}ms."
    ];
}
for my $cause (sort keys %graph_problem_by_cause) {
    push @suggestions, [
        $graph_problem_by_cause{$cause},
        "graph repair",
        "Move graph repair $cause out of normal playback; $graph_problem_by_cause{$cause} repair/reconnect marker(s)."
    ];
}
for my $kind (sort keys %uncorrelated_late_by_kind) {
    push @suggestions, [
        $uncorrelated_late_by_kind{$kind},
        "missing correlation",
        "Add activity/main-hop/cache markers near $kind late events; $uncorrelated_late_by_kind{$kind} warning-late event(s) lacked nearby causes."
    ];
}

print "\nTop remediation suggestions (impact class suggestion)\n";
if (!@suggestions) {
    print "0 none No warning/failure-threshold timing issues found in this log.\n";
} else {
    @suggestions = sort {
        $b->[0] <=> $a->[0] ||
        $a->[1] cmp $b->[1] ||
        $a->[2] cmp $b->[2]
    } @suggestions;
    my $limit = @suggestions < 8 ? @suggestions : 8;
    for my $index (0 .. $limit - 1) {
        my ($impact, $class, $suggestion) = @{ $suggestions[$index] };
        print "$impact $class $suggestion\n";
    }
}

print "\nFailure-threshold late events >= ${failure_ms}ms: $failure_count\n";
exit(($ENV{TIMING_PROBE_FAIL_ON_FAILURES} // "") eq "1" && $failure_count > 0 ? 2 : 0);
PERL
