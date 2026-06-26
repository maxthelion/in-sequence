#!/usr/bin/env bash
set -euo pipefail

# realtime-path-lint — deterministic guard for the Audio Engine Hard Rules on
# the tick / scheduling / sample-trigger code paths. See
# wiki/pages/architecture-guardrails.md ("Audio Engine Hard Rules") and
# docs/plans/2026-06-24-sample-accurate-timing.md ("Enforcing mechanisms").
#
# Every forbidden API is opt-out via a `realtime-allow-<reason>: <why> . Test:
# <name>` comment on the offending line or the line above it (same mechanism for
# every rule below). A bare annotation with no reason / no Test: reference is
# itself a failure.
#
# Rules enforced here:
#   - file IO / main-sync / @MainActor hop on the realtime path (base_forbidden);
#   - graph mutation off the MainAudioGraph owner (graph_mutation);
#   - unannotated DispatchQueue.main.async on the realtime path;
#   - Rule 5: engine.stop()/start() topology change (MainAudioGraph only);
#   - Rule 1 (#39): wall-clock musical-timing source on the tick/scheduling path
#     (ProcessInfo.systemUptime / Date / DispatchTime.now / DispatchSourceTimer);
#   - Rule 4 (#39): disk on the sample-trigger path (scheduleSegment(file:) /
#     AVAudioFile(forReading:) in SamplePlaybackEngine).
#
# Rule 3 (#36, Phase 1) — AU notes are sample-stamped, never main-hopped. NOW
# ENFORCED. On the AU note sink (Sources/Audio/AudioInstrumentHost.swift) forbid
# `startNote(` and `stopNote(` (bare AU note triggering) and `DispatchQueue.main`
# UNLESS annotated `realtime-allow-<reason>: ... Test: <name>`. Phase 1 moved the
# per-note trigger path to `scheduleMIDIEventBlock` (sample-stamped), so the only
# legitimate remaining sites are control-path (graph/preset setup main hops, the
# all-notes-off panic stopNote) — each annotated. A NEW unannotated
# startNote/stopNote/DispatchQueue.main on the note path fails the lint (the
# Rule 3 block below; RealtimePathLintTests plants a violation to prove it).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
rg_bin="${RG_BIN:-$(command -v rg || true)}"
if [[ -z "$rg_bin" ]]; then
  for candidate in \
    "/Applications/Codex.app/Contents/Resources/rg" \
    "/opt/homebrew/bin/rg" \
    "/usr/local/bin/rg"
  do
    if [[ -x "$candidate" ]]; then
      rg_bin="$candidate"
      break
    fi
  done
fi

if [[ -z "$rg_bin" ]]; then
  printf 'realtime path lint requires ripgrep (rg); set RG_BIN to its path\n' >&2
  exit 127
fi

if (($# > 0)); then
  files=("$@")
else
  files=(
    "Sources/Engine/EngineController.swift"
    "Sources/Engine/EngineControllerAudioInput.swift"
    "Sources/Engine/EngineControllerNoteRepeat.swift"
    "Sources/Engine/EngineSlicerDispatcher.swift"
    "Sources/Engine/RouterDispatchState.swift"
    # Tick / scheduling clock files — scanned so Rule 1 (one audio-derived
    # master clock) covers the sanctioned host-time site (AudioMasterClock)
    # and the pump-pacing timer (TickClock).
    "Sources/Engine/AudioMasterClock.swift"
    "Sources/Engine/TickClock.swift"
    "Sources/Audio/MainAudioGraph.swift"
    "Sources/Audio/AudioInstrumentHost.swift"
    "Sources/Audio/SamplerFilterNode.swift"
    "Sources/Audio/SamplePlaybackEngine.swift"
  )
fi

base_forbidden_regex='(AudioFileRef\.resolve|\.fileRef\.resolve|AVAudioFile\(forReading:|FileManager\.default|Data\(contentsOf:|DispatchQueue\.main\.sync|MainActor\.run|Task[[:space:]]*\{[[:space:]]*@MainActor)'
graph_mutation_regex='((^|[^A-Za-z0-9_])audioGraph\.(attach|detach|connect|disconnectOutput|disconnectInput)\(|(^|[^A-Za-z0-9_])engine\.(attach|detach|connect|disconnectNodeOutput|disconnectNodeInput)\(|(^|[^A-Za-z0-9_])reconnect[A-Za-z0-9_]*\()'
default_forbidden_regex="(${base_forbidden_regex}|${graph_mutation_regex})"
failed=0
allow_regex='realtime-allow-[a-z-]+: .+Test: [A-Za-z0-9_]+'

for file in "${files[@]}"; do
  if [[ "$file" = /* ]]; then
    path="$file"
  else
    path="$repo_root/$file"
  fi

  forbidden_regex="$default_forbidden_regex"
  case "$file" in
    */MainAudioGraph.swift|Sources/Audio/MainAudioGraph.swift)
      # MainAudioGraph is the graph owner. Its graph mutations are the owned
      # implementation surface, but it is still linted for file IO and main
      # hops so permissions-sensitive/audio-thread regressions stay visible.
      forbidden_regex="$base_forbidden_regex"
      ;;
  esac

  while IFS=: read -r line text; do
    [[ -z "${line:-}" ]] && continue
    [[ "$text" =~ ^[[:space:]]*// ]] && continue
    previous=""
    if (( line > 1 )); then
      previous="$(sed -n "$((line - 1))p" "$path")"
    fi
    if [[ "$text" =~ $allow_regex || "$previous" =~ $allow_regex ]]; then
      continue
    fi
    printf '%s:%s: realtime path uses forbidden API: %s\n' "$file" "$line" "$text" >&2
    failed=1
  done < <("$rg_bin" -n "$forbidden_regex" "$path" || true)

  while IFS=: read -r line text; do
    [[ -z "${line:-}" ]] && continue
    if [[ ! "$text" =~ $allow_regex ]]; then
      printf '%s:%s: realtime allow annotation must include a reason and Test: reference: %s\n' "$file" "$line" "$text" >&2
      failed=1
    fi
  done < <("$rg_bin" -n 'realtime-allow-' "$path" || true)

  awk -v file="$file" '
    function has_allow(line) {
      return line ~ /realtime-allow-[a-z-]+: .+Test: [A-Za-z0-9_]+/
    }
    /DispatchQueue\.main\.async/ {
      if (!has_allow($0) && !has_allow(previous)) {
        printf "%s:%d: realtime path uses unannotated DispatchQueue.main.async: %s\n", file, NR, $0 > "/dev/stderr"
        failed = 1
      }
    }
    { previous = $0 }
    END { exit failed ? 1 : 0 }
  ' "$path" || failed=1

  # Rule 5 (Audio Engine Hard Rules): never engine.stop()/start() to change
  # topology during playback. MainAudioGraph owns the graph and has a handful of
  # LEGITIMATE engine lifecycle sites (transport start/stop, device-change
  # recovery, one-time master-chain setup, the audio-input full-rebuild
  # fallback). Each of those is annotated with a `routing-lint-allow:` comment.
  # Any engine.stop()/start() that is NOT annotated — e.g. a new one slipped
  # into a per-track/per-bus routing edit function — fails the lint.
  case "$file" in
    */MainAudioGraph.swift|Sources/Audio/MainAudioGraph.swift)
      awk -v file="$file" '
        function has_allow(line) {
          return line ~ /routing-lint-allow:[[:space:]]*.+/
        }
        /engine\.(stop|start)\(/ {
          if ($0 ~ /^[[:space:]]*\/\//) { previous = $0; next }
          if (!has_allow($0) && !has_allow(previous)) {
            printf "%s:%d: routing guardrail (Rule 5) violated: unannotated engine.stop()/start() — only transport start/stop, device recovery, master-chain setup, and audio-input full-rebuild may call these; annotate legitimate sites with `// routing-lint-allow: <reason>`: %s\n", file, NR, $0 > "/dev/stderr"
            failed = 1
          }
        }
        { previous = $0 }
        END { exit failed ? 1 : 0 }
      ' "$path" || failed=1
      ;;
  esac

  # Rule 1 (Audio Engine Hard Rule 1): one audio-derived master clock. On the
  # TICK / SCHEDULING path, never derive a *musical / sounding* time from a wall
  # clock. Forbid `ProcessInfo.processInfo.systemUptime`, `Date(` / `Date.now`,
  # `DispatchTime.now`, and `DispatchSourceTimer` (a timer's deadline) UNLESS the
  # site is annotated `realtime-allow-<reason>: ... Test: <name>` classifying why
  # it is NOT a musical-timing source. The sanctioned classifications are:
  #   - sanctioned-clock: AudioMasterClock's render-origin / host-time anchoring
  #     (THE one site allowed to touch host time for musical timing);
  #   - pump-pacing: TickClock's DispatchSourceTimer wake — paces *when* we
  #     commit, never the sounding frame;
  #   - midi-host: control-path MIDI note-off FLUSH timestamps (repeat/cleanup
  #     teardown) — off the sounding path, no musical position to anchor. The
  #     SOUNDING MIDI-out stamp is now (Phase 3) derived from AudioMasterClock
  #     (`hostSeconds(atMusicalSeconds:)`), NOT wall clock;
  #   - diagnostic: SequencerTimingProbe / DevActivity / control-path (stop,
  #     shutdown, note-off flush) timestamps — not event scheduling.
  # Any NEW unannotated wall-clock-as-timing on these files fails the lint. The
  # `_OverrideForTesting`/`effectivePlaybackTime` default-argument seams are part
  # of the deterministic test harness, not the live musical path; they are
  # annotated where they appear.
  case "$file" in
    */EngineController.swift|Sources/Engine/EngineController.swift \
    |*/EngineControllerAudioInput.swift|Sources/Engine/EngineControllerAudioInput.swift \
    |*/EngineControllerNoteRepeat.swift|Sources/Engine/EngineControllerNoteRepeat.swift \
    |*/EngineSlicerDispatcher.swift|Sources/Engine/EngineSlicerDispatcher.swift \
    |*/RouterDispatchState.swift|Sources/Engine/RouterDispatchState.swift \
    |*/AudioMasterClock.swift|Sources/Engine/AudioMasterClock.swift \
    |*/TickClock.swift|Sources/Engine/TickClock.swift)
      awk -v file="$file" '
        function has_allow(line) {
          return line ~ /realtime-allow-[a-z-]+: .+Test: [A-Za-z0-9_]+/
        }
        /ProcessInfo\.processInfo\.systemUptime|Date\(|Date\.now|DispatchTime\.now|DispatchSourceTimer/ {
          if ($0 ~ /^[[:space:]]*\/\//) { previous = $0; next }
          if (!has_allow($0) && !has_allow(previous)) {
            printf "%s:%d: Rule 1 (one audio-derived master clock) violated: unannotated wall-clock musical-timing source on the tick/scheduling path — only AudioMasterClock may anchor host time for musical timing; pump pacing, MIDI host time, and diagnostics must be annotated `// realtime-allow-<reason>: <classification> . Test: <name>`: %s\n", file, NR, $0 > "/dev/stderr"
            failed = 1
          }
        }
        { previous = $0 }
        END { exit failed ? 1 : 0 }
      ' "$path" || failed=1
      ;;
  esac

  # Rule 4 (Audio Engine Hard Rule 4): triggered playback reads resident buffers
  # from RAM, never streams from disk. On the sample/slice TRIGGER path
  # (SamplePlaybackEngine), forbid `scheduleSegment(` (the file-streaming overload)
  # and `AVAudioFile(forReading:` UNLESS annotated. P2 left exactly two annotated
  # sites: the bounded large-loop / no-resident-buffer streaming fallback
  # (`realtime-allow-file-stream`) and the legacy audition/URL open
  # (`realtime-allow-file-open`). Any NEW unannotated streaming/open in this file
  # fails the lint. (`AVAudioFile(forReading:` is also in base_forbidden_regex
  # above for the whole realtime path; this block additionally pins
  # `scheduleSegment(`, which base_forbidden does not cover.)
  # Rule 3 (Audio Engine Hard Rule 3, #36/Phase 1): AU notes are sample-stamped
  # via scheduleMIDIEventBlock, never a DispatchQueue.main hop or a bare
  # startNote/stopNote on the note/tick path. On the AU note sink
  # (AudioInstrumentHost.swift) forbid `startNote(` and `stopNote(` UNLESS
  # annotated. Phase 1 removed the per-note startNote/stopNote main-hop; the only
  # sanctioned remaining note-off is the all-notes-off panic on the control path
  # (stop/shutdown/preset-silence), annotated `realtime-allow-control-stopnote`.
  # A NEW unannotated startNote/stopNote on this file fails the lint. (Main hops
  # are already covered above: DispatchQueue.main.sync via base_forbidden, and
  # unannotated DispatchQueue.main.async via the shared awk block — the AU
  # graph/preset setup hops are annotated `realtime-allow-main-*`.)
  case "$file" in
    */AudioInstrumentHost.swift|Sources/Audio/AudioInstrumentHost.swift)
      awk -v file="$file" '
        function has_allow(line) {
          return line ~ /realtime-allow-[a-z-]+: .+Test: [A-Za-z0-9_]+/
        }
        /\.startNote\(|\.stopNote\(|[^A-Za-z0-9_]startNote\(|[^A-Za-z0-9_]stopNote\(/ {
          if ($0 ~ /^[[:space:]]*\/\//) { previous = $0; next }
          if (!has_allow($0) && !has_allow(previous)) {
            printf "%s:%d: Rule 3 (AU notes sample-stamped, never main-hopped) violated: unannotated startNote/stopNote on the AU note path — AU notes must be scheduled via scheduleMIDIEventBlock with an AUEventSampleTime; only the control-path all-notes-off panic may call stopNote, annotated `// realtime-allow-control-stopnote: <reason> . Test: <name>`: %s\n", file, NR, $0 > "/dev/stderr"
            failed = 1
          }
        }
        { previous = $0 }
        END { exit failed ? 1 : 0 }
      ' "$path" || failed=1
      ;;
  esac

  case "$file" in
    */SamplePlaybackEngine.swift|Sources/Audio/SamplePlaybackEngine.swift)
      awk -v file="$file" '
        function has_allow(line) {
          return line ~ /realtime-allow-[a-z-]+: .+Test: [A-Za-z0-9_]+/
        }
        /[.[:space:]]scheduleSegment\(/ {
          if ($0 ~ /^[[:space:]]*\/\//) { previous = $0; next }
          if (!has_allow($0) && !has_allow(previous)) {
            printf "%s:%d: Rule 4 (resident buffers, no disk on the trigger path) violated: unannotated scheduleSegment(file:) — triggered playback must scheduleBuffer a resident AVAudioPCMBuffer; file streaming is reserved for bounded large-loop audio and must be annotated `// realtime-allow-file-stream: <reason> . Test: <name>`: %s\n", file, NR, $0 > "/dev/stderr"
            failed = 1
          }
        }
        { previous = $0 }
        END { exit failed ? 1 : 0 }
      ' "$path" || failed=1
      ;;
  esac
done

exit "$failed"
