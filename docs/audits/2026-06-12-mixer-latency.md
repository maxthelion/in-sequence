# Mixer latency audit — laggy slider investigation

Date: 2026-06-11 (filed for 2026-06-12). Read-only audit of the current working tree
(flat-UI merge + uncommitted capture-harness work). All line numbers refer to that tree.

Symptom: changing a mixer slider produced a lagging effect. Ruling: no live control may lag.

---

## 1. Per-control path map

Classification key:
- **(a) live** — direct engine/graph parameter write (mixer-node volume/pan, AU param)
- **(b) per-tick session write** — live-store mutation + engine dispatch on every drag tick
- **(c) throttled** — ThrottledMixValue. NOTE: it is **epsilon-gated only (0.0005), there is NO
  time throttle** — see section 2
- **(d) commit-on-release** — audio does not change until pointer-up

| Control | Drag-tick path | Class | Latency risk | Evidence |
|---|---|---|---|---|
| **Track fader** | `VerticalLevelFader` drag → `updateLevel` → `ThrottledMixValue.update` → `session.setTrackMix` → `store.mutateTrack` (@Observable) + `engineController.setMix` → `refreshEffectiveMixerState` (O(all tracks+buses)) + **`publishSnapshot(changed:.track)`** + debounced flush | b + c | **SEVERE** — see causes #1, #2 | `Sources/UI/MixerView.swift:459-473`, `Sources/App/SequencerDocumentSession.swift:278-292`, `Sources/Engine/EngineController.swift:1140-1149, 2375-2420` |
| **Track pan** | `StudioSlideControl.onChange` → `updatePan` → same `session.setTrackMix` pipeline | b + c | **SEVERE** (identical to fader) | `MixerView.swift:475-484` |
| **Send A/B rotary** | `StudioRotaryKnob.onLiveChange` → `updateSend` → same `session.setTrackMix` pipeline per tick; `onChange` (release) commits via `setTrackMix` again | b + c | **SEVERE**, plus extra graph-rewire hazard crossing 0% (send node attach/detach) | `MixerView.swift:324-337, 424-443`, `Sources/Audio/MainAudioGraph.swift:563-587, 1194+` |
| **Bus fader** | `onSetLevel` → `session.setMixerBusLevel` → scoped `.mixerBusMix` → `EngineController.setMixerBusMix` → **`refreshEffectiveMixerState`** (same O(N) sweep incl. per-track `setTrackSends`) → `MixerBusHost.applyMix` (mixer-node volume/pan — cheap endpoint) | b (scoped, no snapshot publish) | **HIGH** — endpoint cheap, but the full-mixer refresh sweep + per-track send rewires run per tick | `MixerBusStrip.swift:202-209`, `SequencerDocumentSession.swift:349-461`, `EngineController.swift:1154-1160`, `Sources/Audio/MixerBusHost.swift:75-82` |
| **Bus pan** | same as bus fader (`setMixerBusPan`) | b | HIGH (same sweep) | `SequencerDocumentSession.swift:353-355` |
| **Master fader** | Drag: `setLiveMasterOutputGain` → `MainAudioGraph.setMasterOutputGain` → `finalOutputMixer.outputVolume` (clean live path). Release: `session.setMasterOutputGain` → `mutateMasterBus` → `apply(masterBus:)` → `MasterBusHost.apply` → `rebuildAudioGraph` | a (drag) + d (commit) | **HIGH at release** — any gain ≠ 1.0 fails `isUnityPassThrough` → `installMasterChains` → **`engine.stop()` / `engine.start()`** = audible dropout on every release | `MasterOutputColumnView.swift:300-316`, `MasterBusHost.swift:212-261 (247-249 gain≈1 check)`, `MainAudioGraph.swift:659-675` |
| **Crossfader / A-B blend** | `StudioSlideControl.onChange` → `setLiveMasterCrossfader` → overlay + `MasterBusHost.setLiveCrossfaderOverride` → `refreshAudioGraphForPerformanceChange`. Shape-equal path: `setMasterBranchGains` (cheap) + reconfigure enabled inserts per tick (`configureLoFiNode` calls `loadFactoryPreset` per tick). **First tick from unity pass-through (`installedShape == nil`): falls into full `rebuildAudioGraph` → `installMasterChains` → engine stop/start mid-gesture.** No `onEnd` in the mixer column — overlay never committed there | a (steady) / graph rebuild (first tick) | MEDIUM-HIGH at gesture start; MEDIUM if a bitcrusher insert is enabled (factory-preset reload per tick) | `MasterOutputColumnView.swift:36-45`, `MasterBusHost.swift:133-139, 370-401, 350-368` |
| **Track mute** | click → `toggleTrackMute` → **`.fullEngineApply`** → `apply(documentModel:)` (full project export, full snapshot compile, deltas, graph reconciliation) | full rebuild (one-shot) | MEDIUM — single click but tens of ms; feels sticky during playback | `SequencerDocumentSession+Mutations.swift:1336-1343`, `EngineController.swift:900-926` |
| **Track solo** | `setTrackSoloed` → `applyTrackMixPerformanceMutation` → `setMix` + `publishSnapshot(.track)` | scoped + snapshot publish (one-shot) | MEDIUM (same phrase-buffer recompile as cause #1, once) | `SequencerDocumentSession.swift:424-430, 470-476` |
| **Bus mute / solo** | scoped `.mixerBusMix` → `refreshEffectiveMixerState` | b (one-shot) | LOW-MEDIUM | `SequencerDocumentSession.swift:357-363` |
| **Send-return FX sliders (wet, cutoff, res, rate, drive)** | SwiftUI `Slider` binding set per tick → `session.updateSendBusInsert` → `mutateSendBus` → `engineController.apply(sendBus:)` → `MainAudioGraph.installSendBus` → `installSendBuses` → **unconditional `engine.stop()`, reinstall send hosts, reconnect every routed track output, `engine.start()` — per mouse-move** | full graph reinstall per tick | **CATASTROPHIC** — engine stop/start at drag rate | `MixerWorkspaceView.swift:297-303, 371-385, 480-581`, `SequencerDocumentSession+SendBusMutations.swift:5-13, 27-32`, `MainAudioGraph.swift:480-513` |
| **Bus insert enable toggle** | bypass-only change detected → scoped `.mixerBusParameters` → `MixerBusHost.applyParameters` (no rebuild) | a | LOW (good narrowing) | `SequencerDocumentSession.swift:373-392, 506-515` |
| **Inspector level/pan, source-parameter sliders, scalar cell editors** | same `ThrottledMixValue` + `session.setTrackMix` pattern → inherit cause #1/#2 | b + c | HIGH | `InspectorView.swift:7-8,185-222`, `TrackSource/Widgets/SourceParameterSliderRow.swift:10`, `PhraseCellEditors/ScalarValueEditor.swift:8` |

---

## 2. ThrottledMixValue — what it actually is

`Sources/UI/ThrottledMixControl.swift` (the only "throttle" in the drag path):

- **No time-based throttling at all.** `update(_:epsilon:)` only drops a tick when the value
  moved less than `epsilon = 0.0005` (0.05% of a fader) from the **last sent** value. Any real
  pointer movement passes — drag ticks reach the session at full `DragGesture.onChanged`
  rate (~90–120 Hz on modern input devices).
- **Trailing-value guarantee:** partial. `commit()` returns the last live value and clears
  state but for the track fader/pan, `commitLevel`/`commitPan` (`MixerView.swift:470-487`)
  **discard the return value** — they rely on the last passing `update` tick. Worst-case final
  error is < epsilon (inaudible), so functionally fine; sends and master gain do push the
  final value explicitly on release.
- It is an `ObservableObject` with `@Published liveValue` — every passing tick also publishes,
  invalidating the owning strip view (in addition to the store invalidation below).

Conclusion: ThrottledMixValue does not cause skipped/late values (no perceived-lag from
gating), but it also provides **zero protection** against the per-tick cost of everything
downstream. The name oversells it.

---

## 3. Ranked plausible causes of the observed lag

### #1 — `publishSnapshot(changed:.track)` on every track-fader/pan/send drag tick (most likely)

`session.setTrackMix` (`SequencerDocumentSession.swift:278-292`) calls
`publishSnapshot(changed: .track(trackID))` per tick. That does, per mouse-move:

1. `SequencerSnapshotCompiler.compile(changed:)` — because `changed.trackIDs` is non-empty it
   recompiles **all clips owned by the track** *and* **rebuilds every phrase buffer in the
   project** (`SequencerSnapshotCompiler.swift:102-116`: `if changed.layersChanged ||
   !changed.trackIDs.isEmpty` → full `phraseBuffersByID` recompute). On a dense project this
   is many milliseconds of main-thread CPU per tick.
2. `engineController.apply(playbackSnapshot:)` (`EngineController.swift:928-942`) —
   `tickState.installPlaybackSnapshot(..., resetGeneratedStates: true)` (generative track
   state wiped per tick), **`eventQueue.clear()`** (pending scheduled note events dropped per
   tick — audible sequencing stutter/missing notes while dragging during playback), plus
   `reconcilePhraseNavigation` and `reconcileNoteRepeats`.
3. `snapshotPublisher.replace(...)` — @Observable publish that invalidates every snapshot-bound
   visualiser (step grids, phrase views) per tick.

A track's `mix` does not change which notes play; nothing in this work is needed for a level
change. The mix already reaches audio via `engineController.setMix`. This is a pure
per-gesture-tick document-pipeline cost — exactly what the architecture guardrail forbids.

**Why it matches the symptom:** main thread saturates → drag ticks queue up → the thumb and
the audio respond hundreds of ms behind the pointer = "lagging effect."

Confidence: **high** (structural; cost scales with project size, fits "we just overhauled the
mixer and now it lags").

### #2 — `refreshEffectiveMixerState` → per-tick live AVAudioEngine rewires for every zero-send track

`EngineController.setMix` and `setMixerBusMix` both call `refreshEffectiveMixerState`
(`EngineController.swift:2375-2420`), which per tick:

- takes `stateLock` twice and rebuilds `AudioTrackRuntime` entries for all audio tracks;
- for **every** sample/slicer track calls `sampleEngine.setTrackMix` **and**
  `sampleEngine.setTrackSends`;
- `setTrackSends` → `MainAudioGraph.setTrackSendLevels` (`MainAudioGraph.swift:563-587`):
  when a track has **no active sends** (the common case) it takes the
  `!hasSendNodes || !hasActiveSends` branch and calls **`reconnectTrackOutputOnMain`
  unconditionally — `engine.disconnectNodeOutput(source)` + reconnect on the RUNNING engine
  (`MainAudioGraph.swift:1194-1234`) — with no "nothing changed" early-out**;
- plus `syncMidiOutputs`, `updateAudioInputRoutingParameters`, and
  `mainAudioGraph.setMixerBusMix` for every bus (each a `performOnMain` + `graphLock` hop).

With 8 sample tracks at ~60–120 drag ticks/sec that is **500–1000 live graph
disconnect/reconnect operations per second**. AVAudioEngine rewires on a running engine are
slow (ms each) and glitch-prone. This both stalls the main thread and stutters audio.

Confidence: **high** (unconditional rewire is verifiable by reading the code; severity scales
with track count).

### #3 — Send-return FX sliders: full engine stop/start per drag tick

If the slider being dragged was a send-return insert slider (Wet/Cutoff/Res/Rate/Drive in the
mixer's send strips), every binding write goes `updateSendBusInsert` → `apply(sendBus:)` →
`installSendBus` → `installSendBuses` (`MainAudioGraph.swift:480-513`), which **stops the
engine, reinstalls both send-bus hosts, reconnects every routed track output, and restarts the
engine — once per mouse-move**. This is the single worst path in the app: guaranteed audio
dropouts and second-scale lag.

Confidence: **high that the path is broken; medium that this specific slider is the one the
product owner dragged** (depends which slider it was).

### #4 — Master fader release / crossfader first move: master-chain reinstall with engine stop

- Master fader release at any gain ≠ 1.0: `MasterBusHost.rebuildAudioGraph`'s unity shortcut
  requires `abs(gain - 1) < 0.0001` (`MasterBusHost.swift:249`), so a committed gain of e.g.
  0.9 always falls through to `installMasterChains` → `engine.stop()/start()`
  (`MainAudioGraph.swift:671-675`). Drag is smooth (live `outputVolume` writes), then a
  dropout lands **on release** — perceived as the slider "lagging" its effect.
- Crossfader: the first drag tick away from the unity pass-through state (`installedShape ==
  nil`) triggers the same full `installMasterChains` rebuild mid-gesture
  (`MasterBusHost.swift:380-384` → `rebuildAudioGraph`).

Confidence: **medium-high** (deterministic by code; only explains the symptom if the master
fader/crossfader was the dragged control, but the release dropout will be reported as "lag"
by anyone who hits it).

### #5 — Whole-mixer SwiftUI invalidation per tick, compounded by the 60 Hz meter pump

- `MixerView.body` reads `session.store.tracks` / `buses` / `selectedTrackID`
  (`MixerView.swift:56-60`); `store.mutateTrack` per drag tick invalidates the whole mixer —
  every strip, send rotary, menu, and insert list rebuilds per tick.
- Each `MixerChannelStrip.body` reads `channelMeterPublisher(...).displayState`
  (`MixerView.swift:284`), so the strip's **entire body** (header, sends, pan, actions —
  not just the meter lanes) shares invalidation scope with meter updates. During playback
  every strip re-renders at up to 60 Hz (`ChannelMeterBank` single main-queue pump,
  `ChannelMeterBank.swift:85-100`; per-publisher no-op writes are skipped,
  `MainAudioGraph.swift:1777-1782`, but values float continuously while audio plays).
- Two 60 Hz timers run (master publisher's own + the channel bank pump).

On its own this is a moderate render load; stacked on #1/#2 it removes all headroom.
Confidence: **medium** (contributing amplifier, unlikely to be sufficient alone).

### #6 — Not guilty (checked, cleared)

- **Document writes per tick:** none. `scheduleFlushToDocument` is a 150 ms trailing debounce
  (`SequencerDocumentSession.swift:199-226`); flush exports + compares the full project but
  only after the gesture pauses. No undo registration in the drag path.
- **@Observable-mutation-under-stateLock bug class:** `refreshEffectiveMixerState` mutates
  `trackRuntime` internals under `stateLock`, but `trackRuntime` is a plain reference whose
  internals are not observation-tracked; `currentDocumentModel` (observable) is mutated
  outside the lock. Meter publishers deliberately publish outside their locks. No re-entrancy
  found in the mixer paths.
- **AU parameter ramps:** none in these paths; endpoints are `AVAudioMixerNode`
  volume/pan/outputVolume — effectively immediate.
- **`MixerBusHost.applyMix` endpoint:** clean (volume/pan only).

---

## 4. Intended vs actual abstraction

Intended (architecture guardrails, `wiki/pages/engine-architecture.md`,
`wiki/pages/playback-data-path.md`):

- Performance-time controls ride a **scoped live/runtime path** (engine parameter sinks);
  the **document pipeline** (project export, snapshot compile, `apply(documentModel:)`) is
  for durable authored state only. The tick hot path reads `PlaybackSnapshot`, never view
  state. `dispatchScopedRuntimeUpdate` (`SequencerDocumentSession.swift:257-276`) and
  `EngineController.setMix`'s own doc-comment ("writes directly to the live playback sinks
  without rebuilding the document-driven engine pipeline") state the intent precisely.

Actual:

1. `setTrackMix` honors the scoped path (`engineController.setMix`) **and then also runs the
   snapshot pipeline per tick** (`publishSnapshot(changed:.track)`) — the document-oriented
   machinery snuck back into the hot path through the "changed: .track" scoped-compile, which
   isn't scoped at all for tracks (full phrase-buffer rebuild).
2. The "scoped" engine update `setMix`/`setMixerBusMix` fans out to an O(everything) refresh
   (`refreshEffectiveMixerState`) that performs **structural graph work** (send-node
   reconnects) on a parameter change.
3. Two control families bypass the live path entirely and do structural reinstalls per tick
   (send-bus inserts) or per release (master bus at non-unity gain).

So the abstraction exists and is correctly named — it just isn't airtight: parameter changes
leak into structural/document work at three layers.

---

## 5. Fix proposals (smallest first)

1. **Stop publishing snapshots from `setTrackMix`** (1 line + a guard). Mix doesn't affect
   compiled note data; if some consumer needs `snapshot.tracks[].mix`, publish once on
   commit/release, not per tick. Removes phrase recompiles, `eventQueue.clear()`, and
   generated-state resets from the drag path. (`SequencerDocumentSession.swift:290`)
2. **Early-out in `setTrackSendLevels`** when the stored levels equal the new levels and the
   node topology wouldn't change (`hasSendNodes == hasActiveSends` unchanged) — kills the
   per-tick `reconnectTrackOutputOnMain` storm. (`MainAudioGraph.swift:563-587`)
3. **Scope `refreshEffectiveMixerState` to the changed track/bus.** `setMix(trackID:)` only
   needs: recompute effective mute set (cheap), update that track's runtime + sinks, and only
   touch buses when mute/solo actually changed. Skip `syncMidiOutputs` /
   `updateAudioInputRoutingParameters` unless mute state changed. (`EngineController.swift:2375-2420`)
4. **Widen the master unity shortcut to a "gain-only delta" fast path:** in
   `MasterBusHost.rebuildAudioGraph`, when `installedShape == nextShape` (or both represent
   no-insert chains), just `setMasterOutputGain` + `setMasterBranchGains` — never
   `installMasterChains` for a gain or crossfader change. Also pre-install the two-branch
   shape when A/B mode is active so the first crossfader tick doesn't rebuild.
   (`MasterBusHost.swift:212-245`)
5. **Parameter-path for send-bus inserts:** mirror the mixer-bus pattern — `SendBusHost`
   gets `applyParameters` (shape-equal → configure nodes in place); only `installSendBuses`
   on shape changes (add/remove/reorder/kind). Add a `ThrottledMixValue`-style live wrapper
   to the send FX sliders with commit-on-release for the document write.
   (`SequencerDocumentSession+SendBusMutations.swift`, `MainAudioGraph.swift:480-530`)
6. **Add a real time gate to ThrottledMixValue** (e.g. min 16 ms between engine dispatches,
   trailing-edge timer so the final value always lands) — defense in depth so future heavy
   downstream work can't reach mouse-move rate.
7. **Shrink invalidation scope:** move the meter lane into a child view that alone reads
   `displayState` (pass the publisher, not the value, into `MixerStripLevelsColumn`), so meter
   ticks re-render only the lane; have strips read per-track state rather than the whole
   `store.tracks` array in `MixerView.body`.
8. **Fix `configureLoFiNode` per-tick `loadFactoryPreset`** during crossfader drags — only
   reload when the computed preset bucket changes. (`MasterBusHost.swift:350-368`)

---

## 6. Instrumentation plan (one repro session)

Traces exist under `DevActivity` (subsystem `ai.sequencer.SequencerAI.activity`, DEBUG-only,
survive hangs). Capture with:

```
log stream --predicate 'subsystem == "ai.sequencer.SequencerAI.activity"' --info
```

Add these one-line traces (all in already-traced files), then do one repro: start playback,
drag a track fader for ~2 s, release; repeat for bus fader, send rotary, master fader,
crossfader, send-FX wet slider.

| Trace | Where | What it proves |
|---|---|---|
| `session.setTrackMix tick (dt=…ms)` | `SequencerDocumentSession.setTrackMix` entry, log inter-tick delta | actual drag tick rate reaching the session (is epsilon gating doing anything) |
| `compile(changed:.track) took …ms, phrases=…` | around `SequencerSnapshotCompiler.compile(changed:)` call in `publishSnapshot` | cause #1 magnitude per tick |
| `apply(playbackSnapshot) eventQueue cleared n=…` | `EngineController.apply(playbackSnapshot:)` (log `eventQueue` size before `clear()`) | audible-stutter mechanism: events being dropped mid-drag |
| `refreshEffectiveMixerState took …ms tracks=… buses=…` | `EngineController.swift:2375` | cause #2 magnitude |
| `reconnectTrackOutput (live rewire)` | `MainAudioGraph.reconnectTrackOutputOnMain` | count of per-tick live rewires (expect 0 for a pure level change; reality will show N×tickrate) |
| `installMasterChains (engine stop, wasRunning=…)` | `MainAudioGraph.installMasterChains` | cause #4: fires on master-fader release / first crossfader tick |
| `installSendBuses (engine stop)` | `MainAudioGraph.installSendBuses` | cause #3: fires per tick while dragging send-FX sliders |
| `flushToDocumentSync` | already exists (`SequencerDocumentSession.swift:216`) | confirms document flush stays out of the drag (should appear once, ~150 ms after release) |

Reading the log: the dominant cause is whichever trace fires per-tick with the largest
duration. If `reconnectTrackOutput` and `compile(changed:.track)` both fire at tick rate,
causes #1+#2 are confirmed compound. Optionally wrap the same spots in
`os_signpost(.begin/.end)` intervals (same subsystem) to read flame widths in Instruments'
os_signpost track alongside hangs in the Time Profiler.
