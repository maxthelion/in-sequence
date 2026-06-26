// Audio adherence observers — the four SEMANTIC observers that complement the
// deterministic lints (`scripts/diagnostics/realtime-path-lint.sh`,
// `runtime-ownership-lint.sh`) for the Audio Engine Hard Rules.
//
// Same shape + invocation as `.claude/workflows/observer-sweep.js`: a re-runnable
// workflow spec driven by the orchestrator. The `agent`, `phase`, and `parallel`
// globals are provided by the harness that runs the workflow (there is no in-repo
// JS runner; a person or Claude executes it, as observer-sweep is executed). Each
// observer is one `agent()` call with a prompt + a structured-evidence schema.
//
// WHAT THESE ARE FOR. The lints catch the *literal* banned API (a bare
// `systemUptime`, a `scheduleSegment(file:)`, an `engine.stop()`). These
// observers catch what a grep cannot: a new path that re-derives time from a
// wall clock INDIRECTLY (through a helper / a stored seconds value), a routing
// edit that stops the engine THROUGH A HELPER, a sample feature that streams
// from disk "just this once", a `disconnect` not preceded by a silence ramp.
//
// CONTRACT (every observer): WRITE EVIDENCE ONLY. Emit PASS, or a violation list
// where each item is `file:line` + a one-line rationale tying the finding to the
// specific Hard Rule it breaches. Observers DO NOT fix and DO NOT route work —
// synthesis + scheduling happen in the OODA loop (see AGENTS.md "Loop Model"
// and wiki/pages/observer-sweep.md). A violation is evidence for the loop to act
// on, never an auto-fix.
//
// Guardrails: wiki/pages/architecture-guardrails.md → "Audio Engine Hard Rules".
// Plan: docs/plans/2026-06-24-sample-accurate-timing.md → "Adherence observers".

export const meta = {
  name: 'audio-adherence-observers',
  description:
    'Four semantic observers (audio-clock / au-note-path / sample-memory / graph-mutation conformity) that judge INTENT against the Audio Engine Hard Rules and emit file:line evidence for the OODA loop. Complements the deterministic realtime-path / runtime-ownership lints.',
  // Run these on any change touching tick / scheduling / sample / slicer /
  // audio-graph code, AND on a periodic sweep. They run independently, so the
  // default is a parallel fan-out; each can also be invoked on its own.
  triggers: [
    'audio-touching diff (tick, scheduling, sample, slicer, audio-graph paths)',
    'periodic sweep',
  ],
  observers: [
    'audio-clock-conformity',
    'au-note-path-conformity',
    'sample-memory-conformity',
    'graph-mutation-conformity',
  ],
}

// The audio paths each observer reads. Passed as `scope` so a single-file /
// diff-only invocation can narrow it; the periodic sweep reads them all.
const AUDIO_PATHS = {
  clock: [
    'Sources/Engine/AudioMasterClock.swift', // THE sanctioned host-time site
    'Sources/Engine/TickClock.swift', // pump pacing only
    'Sources/Engine/EngineController.swift',
    'Sources/Engine/EngineControllerAudioInput.swift',
    'Sources/Engine/EngineControllerNoteRepeat.swift',
    'Sources/Engine/EngineSlicerDispatcher.swift',
    'Sources/Engine/RouterDispatchState.swift',
  ],
  auNote: ['Sources/Audio/AudioInstrumentHost.swift'],
  sample: ['Sources/Audio/SamplePlaybackEngine.swift'],
  graph: [
    'Sources/Audio/MainAudioGraph.swift',
    'Sources/Audio/TrackInsertChainHost.swift',
    'Sources/Audio/AudioInstrumentHost.swift',
    'Sources/Audio/SamplePlaybackEngine.swift',
  ],
}

// Shared evidence shape. An observer returns verdict PASS with an empty
// violations list, or FLAG with one entry per finding.
const OBSERVER_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['observer', 'guardrail', 'verdict', 'violations', 'notes'],
  properties: {
    observer: { type: 'string' },
    guardrail: {
      type: 'string',
      description: 'the Audio Engine Hard Rule number + title this observer maps to',
    },
    verdict: { type: 'string', enum: ['PASS', 'FLAG'] },
    violations: {
      type: 'array',
      description: 'one entry per finding; empty when verdict is PASS',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['location', 'finding', 'rule_breached', 'why_not_an_exception'],
        properties: {
          location: { type: 'string', description: 'file:line of the offending shape' },
          finding: {
            type: 'string',
            description: 'one line: what the code does that breaches the rule (the INDIRECT shape, not just the literal API)',
          },
          rule_breached: {
            type: 'string',
            description: 'the specific Hard Rule (1-5) this finding breaches',
          },
          why_not_an_exception: {
            type: 'string',
            description: 'why this is NOT one of the sanctioned exceptions listed for this observer',
          },
        },
      },
    },
    notes: {
      type: 'string',
      description: 'sanctioned exceptions confirmed in scope, confidence, and anything the next loop step should know',
    },
  },
}

// Common preamble: the contract every observer obeys.
const CONTRACT = `You are a SEMANTIC audio-adherence observer for in-sequence (Swift/SwiftUI/AVAudioEngine/CoreMIDI generative DAW), at /Users/maxwilliams/dev/in-sequence.

Read the diff/codebase and judge INTENT against the Audio Engine Hard Rules in wiki/pages/architecture-guardrails.md. You COMPLEMENT the deterministic lints (scripts/diagnostics/realtime-path-lint.sh, runtime-ownership-lint.sh): the lints already catch the literal banned API token. YOUR job is what a grep cannot see — the SAME violation reached INDIRECTLY (through a helper, a stored value, a default argument, a new feature flag, a "just this once"), or a required protective shape that is MISSING.

CONTRACT — non-negotiable:
- WRITE EVIDENCE ONLY. Do not edit code. Do not route or schedule work. A violation is evidence for the OODA loop, not an auto-fix.
- Output verdict PASS (no violations) or FLAG with one entry per finding.
- Every finding MUST carry file:line, a one-line rationale tying it to the SPECIFIC Hard Rule it breaches, and why it is NOT one of the sanctioned exceptions below.
- Do not flag a sanctioned, correctly-annotated exception. Do not vacuously PASS — if you cannot reach a path, say so in notes rather than asserting clean.
- An existing \`realtime-allow-…: <reason> . Test: <name>\` or \`routing-lint-allow: <reason>\` annotation marks a deliberate exception; verify the annotation's CLAIM is true (the site really is control-path / setup / bounded-large-loop), then do not flag it. A bare/over-broad annotation whose claim does not hold IS a finding.`

phase('audio-clock-conformity')
const clock = await agent(
  `${CONTRACT}

OBSERVER: audio-clock-conformity
MAPS TO: Hard Rule 1 (one audio-derived master clock) + Hard Rule 2 (schedule ahead, never fire "now").

FLAG when MUSICAL / SOUNDING time is derived from a wall clock rather than the unified AudioMasterClock:
- any use of \`ProcessInfo.processInfo.systemUptime\`, \`Date(\`/\`Date.now\`, \`DispatchTime.now\`, or a \`DispatchSourceTimer\` deadline whose value flows into an event's SOUNDING time — including INDIRECTLY (a seconds value stored then later turned into an AVAudioTime/host time; a helper that returns "now"; a new code path that recomputes a deadline instead of asking AudioMasterClock).
- any scheduled event that is fired "now" instead of stamped with a FUTURE time. Confirm every scheduled audio/AU/MIDI event carries a future \`sampleTime\` / \`AUEventSampleTime\` / \`MIDITimeStamp\` handed to the sink ahead of time (lookahead), NOT triggered the instant a timer fires.
- evidence MUST name WHICH clock the value originated from (e.g. "systemUptime via X.deadline at file:line") and trace the path to the sounding stamp.

SANCTIONED EXCEPTIONS (do NOT flag):
- \`AudioMasterClock\` is THE one sanctioned site that may touch host time / systemUptime for musical timing: its render-origin capture/upgrade, the provisional pre-render origin fallback, and the final \`AVAudioTime(hostTime:)\` stamp. The host-time ORIGIN comes from the render clock's hostTime; the musical OFFSET comes from the tempo map — neither is a free-running wall clock.
- \`TickClock\`'s \`DispatchSourceTimer\` wake is PUMP PACING only — it decides WHEN we commit lookahead, never the sounding frame. Allowed, annotated \`pump-pacing\`.
- the control-path note-off FLUSH (repeat/cleanup/teardown, e.g. \`flushDetachedMIDINoteOffs\`) is an ALLOWED wall-clock exception — it is off the sounding path with no musical position to anchor.
- \`SequencerTimingProbe\` / \`DevActivity\` diagnostic timestamps, and \`*OverrideForTesting\` / offline-render seams, are not the live musical path.
- MIDI-out's own host-time path is sanctioned where Phase 3 derives it from AudioMasterClock (\`hostSeconds(atMusicalSeconds:)\`); a RAW wall-clock value reaching a MIDITimeStamp on the sounding path is still a finding.

SCOPE: ${JSON.stringify(AUDIO_PATHS.clock)} (narrow to the diff when invoked on a change).`,
  { phase: 'audio-clock-conformity', label: 'audio-clock-conformity', schema: OBSERVER_SCHEMA }
)

phase('au-note-path-conformity')
const auNote = await agent(
  `${CONTRACT}

OBSERVER: au-note-path-conformity
MAPS TO: Hard Rule 3 (AU notes are sample-stamped via scheduleMIDIEventBlock, never main-hopped).

FLAG on the AU NOTE / TICK path:
- any \`DispatchQueue.main\` hop (\`.async\` or \`.sync\`), \`MainActor.run\`, or \`Task { @MainActor … }\` that carries a per-note trigger — including INDIRECTLY (a helper like the old \`performOnMainAsync\` wrapping \`startNote\`; a closure dispatched to main that ends in a note).
- any bare \`startNote(\` / \`stopNote(\` used to SOUND or release a note on the trigger path.
- any note-off scheduled by WALL CLOCK (e.g. \`queue.asyncAfter(deadline: .now() + length)\`) instead of a sample-stamped note-off.
- CONFIRM the positive shape: AU note-on AND note-off both go through \`AUAudioUnit.scheduleMIDIEventBlock\` with an \`AUEventSampleTime\` derived from the unified clock. If scheduleMIDIEventBlock is absent on the note path, that is a finding.

SANCTIONED EXCEPTIONS (do NOT flag):
- the all-notes-off PANIC \`stopNote\` on the CONTROL path (stop / shutdown / preset-silence) — annotated \`realtime-allow-control-stopnote\`. It is not the per-note trigger path.
- main hops for AU GRAPH SETUP and PRESET work (load/attach/connect/preset assignment) — annotated \`realtime-allow-main-*\`. These are control-path, not the note/tick trigger path.
- a deliberate note DROP when an AU exposes no scheduleMIDIEventBlock (rather than falling back to a startNote main hop) is the CORRECT degradation, not a violation.

NOTE: P1 (commit 7d2e6b5d) removed the debt main-hop note path and added a leaf \`auMutationLock\`; this observer keeps that hop from returning.

SCOPE: ${JSON.stringify(AUDIO_PATHS.auNote)}.`,
  { phase: 'au-note-path-conformity', label: 'au-note-path-conformity', schema: OBSERVER_SCHEMA }
)

phase('sample-memory-conformity')
const sampleMem = await agent(
  `${CONTRACT}

OBSERVER: sample-memory-conformity
MAPS TO: Hard Rule 4 (triggered playback reads resident buffers from RAM, never streams from disk).

FLAG when a TRIGGER path can reach disk:
- any \`scheduleSegment(file:)\` (the file-streaming overload), \`AVAudioFile(forReading:)\`, \`cachedFile(url:)\`, or \`AudioFileRef\`/\`.fileRef.resolve\` REACHABLE from a slice / one-shot / drum-hit / note-repeat TRIGGER — including INDIRECTLY (a default-argument fallback that streams when no resident buffer is set; a new "preview"/"audition"/"reverse"/"envelope" branch that opens a file; a code path that lazily loads on first trigger instead of warming first).
- the classic regression: a forward, no-envelope slice that falls through to \`scheduleSegment(file:)\` instead of \`scheduleBuffer\` (the pre-P2b default). Confirm the COMMON forward case schedules a resident \`AVAudioPCMBuffer\` via \`scheduleBuffer\`, and that an un-warmed slice is WARMED before it can fire, never streamed.

SANCTIONED EXCEPTIONS (do NOT flag):
- exactly the EXPLICITLY-ANNOTATED bounded large-loop / no-resident-buffer streaming fallback (\`realtime-allow-file-stream\`, e.g. recorded audio-input loops where resident cost is prohibitive). Verify the annotation's claim: warmed \`PreparedSampleAsset\` triggers must take the resident \`scheduleBuffer\` branch, and only the large-loop case reaches the stream branch. If a NORMAL triggered slice can reach the annotated stream site, the annotation's claim is false → FLAG.
- the legacy audition/URL open annotated \`realtime-allow-file-open\` IF it is genuinely off the trigger path.

NOTE: P2b (commit 52fd56c1) made resident \`scheduleBuffer\` the default and reserved \`scheduleSegment(file:)\` for the annotated large-loop exception.

SCOPE: ${JSON.stringify(AUDIO_PATHS.sample)}.`,
  { phase: 'sample-memory-conformity', label: 'sample-memory-conformity', schema: OBSERVER_SCHEMA }
)

phase('graph-mutation-conformity')
const graph = await agent(
  `${CONTRACT}

OBSERVER: graph-mutation-conformity
MAPS TO: Hard Rule 5 (routing is gain + bypass on a fixed graph; never stop/start for topology during playback; never disconnect a sounding node without ramping to silence first).

FLAG:
- any \`engine.stop()\` / \`engine.start()\` tied to a TOPOLOGY change during playback — including INDIRECTLY (a routing/insert/send/scene helper that stops the engine to re-wire; a "rebuild" that bounces the engine instead of editing the fixed graph). Lifecycle start/stop (transport, device-change recovery, one-time master-chain setup, the audio-input full-rebuild fallback) is NOT a topology edit.
- any \`attach\`/\`detach\`/\`connect\`/\`disconnect\`/\`reconnect\` performing a topology change during playback that is NOT expressed as a gain ramp / bypass toggle on the pre-provisioned fixed graph.
- THE key semantic check the lint cannot do: a \`disconnect\`/\`detach\` of a node that is (or may be) SOUNDING that is NOT first ramped to silence. Confirm every live disconnect of a sounding node is wrapped by the ramp-to-silence guard (e.g. \`withTrackGainRampedToSilence(source:work:)\`: ramp the gain stage to 0 via \`MixerGainRamp\`, run the splice on the down-ramp completion, ramp back) and that the disconnect runs on a FRESH main hop, not under a lock held across the ~12 ms wait. A hard-disconnect of a sounding node = FLAG even if the literal \`disconnect\` token is "owned" by MainAudioGraph.

SANCTIONED EXCEPTIONS (do NOT flag):
- \`engine.stop()/start()\` at the annotated lifecycle sites (\`routing-lint-allow:\` — transport, HAL renegotiation full-rebuild, master-chain setup).
- disconnects on an engine-STOPPED or already-MUTED/silent track may take the synchronous path (no sounding node to click) — verify the guard's gating actually proves it is silent.
- structural add/remove that ramps to silence before any disconnect (the sanctioned ramp-before-disconnect / fast-path-ready gating shape) and uses the live path / pre-attached pool.

NOTE: shared with the fixed-superset routing plan; guards the whole audio layer. The sanctioned shapes are ramp-before-disconnect and fast-path-ready gating.

SCOPE: ${JSON.stringify(AUDIO_PATHS.graph)}.`,
  { phase: 'graph-mutation-conformity', label: 'graph-mutation-conformity', schema: OBSERVER_SCHEMA }
)

// Periodic-sweep convenience: run all four independently in parallel. (For an
// audio-touching diff, invoke only the observer(s) whose SCOPE the diff hits.)
export async function sweep() {
  return parallel([() => clock, () => auNote, () => sampleMem, () => graph])
}

return {
  clock,
  auNote,
  sampleMem,
  graph,
}
