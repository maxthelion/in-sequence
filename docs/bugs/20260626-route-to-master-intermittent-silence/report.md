# Intermittent route-to-master / drum-part-add rebuilt-voice-pool silence

- Date: 2026-06-26
- Area: Audio routing/playback — SamplePlaybackEngine prepared-track rebuild + deferred-repair gate; MainAudioGraph ramp-to-silence routing splice
- Status: Fixed (uncommitted; reworked after adversarial review — PREVENT the disconnect, not recover from it)
- Related: task #57; residual of #53 "route-to-master voice-loss silence"; sibling of
  docs/bugs/20260626-route-switch-teardown-hard-cut (the committed bus-pool hard-cut — deliberately NOT changed).

## Symptom

The routing-stress rig (scripts/visual-scenarios/routing-stress.sh) INTERMITTENTLY reports a track that
should stay/become audible staying silent (peak=-inf) for the whole audibility poll window after its MASTER
voice pool is (re)built DURING PLAYBACK. Two manifestations of the SAME root cause:

- SILENCE routeTrack-1-to-master: track1 stayed silent — routing a bus-routed track back to master
  (setTrackOutputBus(busID:nil) -> .teardownBus -> rebuild master pool).
- SILENCE drumGroupAddPart-0-from3: track8 stayed silent — a freshly-ADDED sample track whose master pool is
  built while the engine plays.

Intermittent (timing-dependent) and pre-existing on the clean baseline.

## Root cause (the decisive one)

A live rebuild of a track's prepared MASTER voice pool wires the new voices/mixer/filter and then publishes
the track as fast-path-ready. But the freshly-issued `engine.connect(...)` edges are NOT atomically visible to
a concurrent TICK-THREAD `play()` on the just-published voice. On the unlucky interleaving the tick thread
selects a voice whose render chain is not yet committed and calls `AVAudioPlayerNode.play()`, which throws:

    com.apple.coreaudio.avfaudio: player started when in a disconnected state

`startVoiceSafely` catches that, returns false, and the fast path calls `deferPreparedTrackRepair`, which marks
the track in `deferredPreparedTrackRepairIDs` and drops it from `fastPathReadyTrackIDs`. From then on the tick
path early-returns on `isPreparedTrackRepairDeferred(...)` and DROPS every trigger.

The trap: the deferred-repair set was a ONE-WAY gate. The original design deliberately deferred WITHOUT
scheduling a repair (to avoid a per-trigger "repair storm" — see the old
`test_backgroundFastPathFailureDefersRepairInsteadOfMainHopRepairStorm`). So nothing ever re-ran the repair:
the track stayed in `deferredPreparedTrackRepairIDs` and SILENT for the rest of the session. Whether the
initial `play()` lost the disconnect race is pure timing -> intermittent.

### Trace evidence (silent run)

    route-to-master teardownBus start track=2B37C89E...
    route-to-master teardownBus done
    dropped sample trigger: play threw ... "player started when in a disconnected state"   <- tick play on uncommitted chain
    deferred prepared sample graph repair track=2B37C89E... reason=post-failure             <- track marked deferred
    dropped sample trigger: play threw ... "player started when in a disconnected state"   <- ...and stays deferred
    deferred prepared sample graph repair track=2B37C89E... reason=post-failure
    (repeats for the rest of the run -> permanent silence)

A `reconnect DONE ... sourceOut=false` probe at the rebuild instant confirmed the new filter->fanout edge is
not yet effective synchronously when the rebuild returns.

After the GATE rework this trace no longer appears: the track is removed from `fastPathReadyTrackIDs` for the
whole synchronous rebuild window and only re-added once `isPreparedTrackPoolReadyForPlayback` confirms the
chain is connected, so the tick path never selects the half-rebuilt voice and `play()` is never called on a
disconnected node. The rig logs 0 "deferred prepared sample graph repair" events per run (was ~100+).

## A secondary, related contributor (also fixed)

The route-to-master / rebuild path issues several `connectTrackOutput`s in quick succession. Each used to take
the ramp-to-silence DEFERRED path (a ~12 ms gain dip, splice on the completion). Overlapping deferred dips on
the same persistent send FANOUT raced: a second cycle captured the first cycle's MID-DIP `outputVolume` as its
"restore" level and ramped "back" to that near-zero transient, and overlapping reconnects could leave the
filter momentarily disconnected from the fanout — widening the disconnect window the tick race exploits.

## Fix (reworked: PREVENT the disconnect, not recover from it)

The first cut RECOVERED from the disconnect with an unbounded self-heal (~100+ defers/run). Adversarial review
flagged that as a band-aid: a genuinely-unconnectable track could oscillate forever, and `prepareTrack`
re-published the track fast-path-ready BEFORE the rebuilt connection was proven in place, so every tick
re-failed and re-deferred. The rework PREVENTS the race instead.

1. **The fast-path-ready GATE (the watertight prevention).** A track is dropped from `fastPathReadyTrackIDs`
   BEFORE the teardown/disconnect/reconnect window of EVERY prepare/repair/route branch (under the lifecycle
   lock), the synchronous topology edit runs on main, and the track is re-published fast-path-ready ONLY after
   VALIDATING that its full output chain is actually connected — the same `outputConnectionExists`-backed
   predicate (`isPreparedTrackPoolReadyForPlayback` / `isBusVoicePoolReadyForPlayback`) the repair path already
   used. Because the disconnect→reconnect window is synchronous on main and the track is invisible to the tick
   path throughout it, a concurrent tick-thread `play()` can NEVER select a voice whose chain is mid-rebuild →
   it never lands a `play()` in the disconnected window → no "player started when in a disconnected state" → no
   defer. The steady-state defer count drops from ~100/run to **0**. (SamplePlaybackEngine:
   `publishPreparedTrackFastPathIfConnected` / `publishBusTrackFastPathIfConnected`, wired into `prepareTrack`,
   `setTrackOutputBus`, `repairPreparedTrackGraph`, `validatePreparedTrackGraphs`.)

2. **The self-heal is now ONLY a bounded last-resort backstop.** `deferPreparedTrackRepair` keeps a per-track
   attempt counter (`deferredPreparedTrackRepairAttempts`) with a HARD CAP (`maxDeferredRepairAttempts = 3`)
   and linear backoff (`asyncAfter(attempt * 20 ms)`). After the cap it logs ONCE (DevActivity) and STOPS
   scheduling — it can never oscillate or pin the main thread. The counter resets to 0 whenever a track is
   successfully (gate-)published, so a healthy track never accumulates. With the gate in place this path is
   effectively dead in steady state (0 fires in the rig); it exists only for an unforeseen engine-level
   disconnect.

3. **Setup/repair splice is synchronous (ramped:false) — but never hard-cuts a sounding sibling.**
   `connectTrackOutput` gains a `ramped` param; setup/repair pass `ramped:false` so the rebuild lands
   immediately and deterministically (avoiding the overlapping-deferred-dip fanout race that widened the
   disconnect window). The shared per-track fanout, however, carries ALL the track's voices, so a repair
   triggered by one voice could still hard-disconnect a SIBLING that is sounding (Hard Rule 5). Guard: the
   synchronous splice is taken ONLY when the gain stage is genuinely not passing audio — engine stopped, OR
   the fanout has no live INPUT+OUTPUT edge pair (the common repair case: the filter→fanout INPUT is exactly
   what we are rewiring, so the fanout has no input and is silent). If the fanout is fed AND has a downstream
   edge while running (a sibling could be sounding), the splice PROMOTES to the ramped path (dip to silence
   first). The genuine live-sounding reroute paths (audio-input mixer reroute, FX-insert chain rebuild,
   single-leg filter reroute) keep the ramp. (MainAudioGraph.connectTrackOutput.)

4. **Settled-target restore (kept from the first cut, with the invariant hole closed).** The ramp-to-silence
   restore reads MixerGainRamp's recorded SETTLED target, not the live (possibly mid-dip) outputVolume; the
   transient down-ramp is marked non-settling; the fanout is seeded settled=1.0 on creation; settled targets
   are forgotten on teardown. The invariant is "settledTarget == the node's intended rest level". That was
   VIOLATED for audio-input tracks: their host wrote `outputMixer.outputVolume` DIRECTLY for mute/level
   (bypassing MixerGainRamp), so a mute left settledTarget stale at a prior audible level — and a later routing
   change's restore AUDIBLY UN-MUTED the track (a regression vs the pre-fix read-live-volume behaviour). Fix:
   ALL audio-input gain-stage writes now go through `MixerGainRamp.setImmediate`, so settledTarget always
   tracks the intended rest level for every track kind (sample/AU/audio-input).
   (MainAudioGraph.applyAudioInputRoutingParametersOnMain + reconnectAudioInputSourceOnMain.)

5. **Recycled-node hygiene.** `forgetSettledTarget` is now also called on the AU host shutdown
   (`AudioInstrumentHost.shutdown`) and audio-input host teardown (`teardownAudioInputRoutingOnMain`) — both
   detach routing gain stages driven by MixerGainRamp — so a node recycled at the same ObjectIdentifier cannot
   inherit a stale rest level.

None of these are sleeps, rig-assertion masks, or band-aids. None defer the bus-pool teardown (Hard Rule 5 /
the separate hard-cut bug). None hold the lifecycle lock across an engine connect/disconnect.

## Proof

- Deterministic unit tests:
  - RampBeforeDisconnectTests.test_overlappingRoutingSplices_restoreToTrueLevel_notMidDipTransient — two
    overlapping ramp-to-silence cycles on a sounding fanout restore to the true level (1.0), not a mid-dip
    transient. (Kept; proves the settled-target restore.)
  - MainAudioGraphTests (in MasterMeterPublisherTests, co-located with the other audio-input test):
    test_audioInputMute_thenRoutingChange_staysSilent_noMuteEscape — an audio-input track is made audible,
    rerouted while audible (seeding the settled target), MUTED, then rerouted while muted. The muted track
    must STAY silent across the reroute. Proven to FAIL on the pre-fix direct-write code (the reroute restore
    un-muted the gain stage back to 0.8 — the mute escape) and PASS after routing the host's mute/level
    writes through MixerGainRamp.setImmediate.
  - SamplePlaybackEngineTests.test_backgroundFastPathFailureDefersThenSelfHealsOnceNoStorm — a forced
    fast-path failure defers the track and self-heals via a SINGLE bounded backstop repair (deferred flag
    cleared, voice reconnected) with no storm. (The backstop now also has a hard cap + backoff; the rig
    proves it never fires in steady state.)
- Routing-stress rig (scripts/visual-scenarios/routing-stress.sh, real-HAL headless, sample-only): 7
  consecutive runs ALL GATE: PASS / SILENCE=0, each with a STEADY-STATE DEFER COUNT of 0 (counted from the
  DevActivity unified-log "deferred prepared sample graph repair" trace over each run's time window), 0
  backstop-CAPPED events, and 0 fast-path-gate-WITHHELD events. This is the decisive evidence the GATE
  PREVENTS the disconnect race rather than recovering from it: the prior (recover) build logged ~100+
  defers/run; the gate build logs 0.
- Audio suites green: MainAudioGraphTests, MasterMeterPublisherTests, SamplePlaybackEngineTests,
  RampBeforeDisconnectTests, EngineControllerMuteTests, EngineControllerRoutedMuteTests.
- Lints green: realtime-path-lint.sh, runtime-ownership-lint.sh. Build green.

## Files changed

- Sources/Audio/SamplePlaybackEngine.swift — the fast-path-ready GATE
  (publishPreparedTrackFastPathIfConnected / publishBusTrackFastPathIfConnected: validate the chain before
  re-publishing fast-path-ready), wired into prepareTrack / setTrackOutputBus / repairPreparedTrackGraph /
  validatePreparedTrackGraphs (all rebuild branches now drop fast-path BEFORE the disconnect window and
  re-add only after validation); the self-heal reworked into a bounded, capped, backed-off backstop
  (deferredPreparedTrackRepairAttempts + maxDeferredRepairAttempts); setup/repair connectTrackOutput uses
  ramped:false; sparse DevActivity breadcrumbs (gate-withheld, backstop-capped, route-to-master).
- Sources/Audio/MainAudioGraph.swift — connectTrackOutput `ramped` param with a sibling-sustain guard
  (promote to ramped when the fanout is fed AND has a downstream edge while running); ramp restore from the
  settled target; transient down-ramp non-settling; detached-source restore safety; trackGainStageForTesting
  accessor; audio-input mute/level writes routed through MixerGainRamp.setImmediate (mute-escape fix);
  forgetSettledTarget on audio-input host teardown.
- Sources/Audio/MixerGainRamp.swift — per-node settled-target tracking + settledTarget/forgetSettledTarget.
- Sources/Audio/AudioInstrumentHost.swift — forgetSettledTarget on AU host shutdown (recycled-node hygiene).
- Tests/SequencerAITests/Audio/RampBeforeDisconnectTests.swift — overlapping-splice restore regression test.
- Tests/SequencerAITests/Audio/MainAudioGraphTests.swift — audio-input mute-escape regression test.
- Tests/SequencerAITests/Audio/SamplePlaybackEngineTests.swift — bounded self-heal backstop test.

## Residual risk / not verified unattended

- The GATE eliminates the disconnect-window race in steady state (0 defers across the rig runs), so the
  deeper structural cause (live rebuild connections not atomically visible to a concurrent tick play) is now
  PREVENTED for every path the rig exercises, not merely recovered from. The bounded backstop remains as a
  belt-and-braces last resort for an unforeseen engine-level disconnect; it is capped (3 attempts + backoff)
  so it can never oscillate or pin main, and it never fires in the rig.
- The rig is sample-only, output-only, serial, real-HAL headless. AU / audio-input destinations and
  concurrent-op cases still need a human real-audio pass. The audio-input mute-escape fix is proven at the
  graph/engine-state level (no mic) by the new regression test; its acoustic behaviour with a real mic is
  not part of the unattended tier.

Status: RESOLVED — 7d8aecf6 (prevent-the-disconnect gate)
