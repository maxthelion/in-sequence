# Concurrency Audit — Race Conditions & Deadlocks Across Engine/Audio/UI

Date: 2026-06-12 (audited working tree of `main`)
Scope: `Sources/Engine`, `Sources/Audio`, `Sources/App` session layer, tap/render callbacks.
Method: read-only audit of every lock region, every `DispatchQueue...sync`, every atomic/ring,
and every tap block; blocking graph built by hand. No code was changed.

---

## 1. The lock + queue topology as actually built

### Execution contexts

| Context | Created at | Runs |
|---|---|---|
| **Main thread / MainActor** | — | SwiftUI bodies, `SequencerDocumentSession` (@MainActor), *all* AVAudioEngine graph mutation (`MainAudioGraph.performOnMain*`), meter pump timers (60 Hz `DispatchSourceTimer` on `.main`), all `@Observable` publication |
| **Tick queue** `ai.sequencer.SequencerAI.TickClock` | TickClock.swift:16 | `processTick` → prepare/dispatch, audio-input scheduling, transport atomic writes |
| **AudioInstrumentHost queue** (one per host) | AudioInstrumentHost.swift:39 | AU instantiation, note on/off dispatch (which hops `main.sync` per note) |
| **Capture publication queue** `…AudioInputCapturePublication` | EngineController.swift:93 | 33 ms capture-drain timer, `readAudioInputCaptureStore` bodies |
| **Recording persistence queue** (utility QoS) | EngineController.swift:109 | WAV + sidecar writes |
| **CommandQueue private queue** | CommandQueue.swift:5 | tiny `queue.sync` enqueue/dequeue regions (leaf, no nesting) |
| **CoreAudio tap threads** | installTap sites | master meter tap (MainAudioGraph.swift:982), channel meter taps (:1076), audio-input capture tap (:1466), master-render file write (:959) |
| **`DispatchQueue.global`** | AudioEffectChoice.swift:97 | AU effect component scan |

### Locks

`EngineController.stateLock` (the big one), `phraseNavigationLock`, `stepOrderPendingLock`,
`documentApplyLock`, `TickStateBuffer.lock`, `EventQueue.lock`,
`MainAudioGraph.graphLock` (only ever taken *inside* main-thread closures — deliberate),
`masterRenderLock`, `SamplePlaybackEngine.lifecycleLock`, `MasterBusHost.lock`,
`ChannelMeterBank.lock`, `AudioInputCaptureStore.lock`, `AudioInstrumentHost.snapshotLock`.

### Blocking (sync) edges

```
main ──queue.sync──────────────► tick queue        TickClock.stop/start/bpm/isRunning (TickClock.swift:102)
tick ──DispatchQueue.main.sync─► main              MainAudioGraph.performOnMain* (MainAudioGraph.swift:1551,1589)
                                                   via processTick paths (see D1/D2)
main ──queue.sync──────────────► host queue        AudioInstrumentHost.captureStateBlob:308,
                                                   presetReadout:323, loadPreset:350
host queue ──main.sync─────────► main              AudioInstrumentHost.performOnMain (:72,88) — per note on/off
main|tick ──queue.sync─────────► publication queue readAudioInputCaptureStore (EngineController.swift:2325)
main|tick [holding stateLock] ──► publication queue  (lock-held sync edge, consistent order)
tick [holding stateLock] ──main.sync──► main       audioInputCaptureFormat (D1 — the bad edge)
any ──queue.sync───────────────► CommandQueue      leaf, safe
```

**Cycles present in this graph** (each is a finding below):

1. `main → tick (TickClock sync)` × `tick → main (performOnMain)` — D2
2. `main → stateLock` × `tick: stateLock → main.sync` — D1
3. `main → host queue (queue.sync)` × `host queue → main.sync` — D3

---

## 2. Findings — ranked by severity

### DEADLOCK-POSSIBLE

---

#### D1. Tick queue does `DispatchQueue.main.sync` **while holding `stateLock`** (capture-begin path)

**Evidence**
- `EngineController.advanceAudioInputSchedulingLocked` wraps its whole body in `withStateLock` — EngineController.swift:2648–2707.
- Inside that lock it calls `beginAudioInputCapture(&runtime, at:)` (:2670) →
  `audioInputCapturePlan(trackID:bars:)` (:2712) →
  `mainAudioGraph.audioInputCaptureFormat(trackID:)` (:2740) →
  `performOnMainReturning` → **`DispatchQueue.main.sync`** (MainAudioGraph.swift:340, 1589).
- Caller is `processTick` (:1579) on the tick queue, so the tick queue is parked in `main.sync`
  with `stateLock` held.

**Interleaving that hangs**
1. User arms an audio-input track; recording begins at the next bar boundary.
2. While recording is pending, the input panel UI reads engine state at meter rate —
   e.g. `audioInputRuntime(for:)` (:627–630) or `audioInputRuntimeTrackIDs` (:643), both
   `withStateLock` on the **main** thread.
3. Bar boundary tick: tick queue takes `stateLock`, reaches `audioInputCaptureFormat`,
   enqueues a `main.sync` block.
4. Main thread is simultaneously inside `stateLock.lock()` (step 2) — parked in the lock,
   not draining the main queue.
5. Tick waits for main; main waits for `stateLock`; nothing ever runs. Hard deadlock.

The same hang also closes through `clock.stop()` / `setBPM` (main parked in TickClock's
`queue.sync` while the tick queue is parked in `main.sync`).

**Proposed fix**
Resolve the capture format *before* taking `stateLock`: snapshot
`mainAudioGraph.audioInputCaptureFormat(trackID:)` for every audio-input track at the top of
`advanceAudioInputScheduling` (outside the lock), pass the formats into the locked region.
Generally: enforce the invariant *no `performOnMain*` call is reachable while `stateLock` is
held* (the codebase already documents the mirror-image rule for `graphLock`).

---

#### D2. Main↔tick AB-BA via `processTick`'s synchronous graph calls — the previously-fixed class, still live on the audio-input paths

**Evidence — tick → main edges inside `processTick`** (all `DispatchQueue.main.sync` via
`MainAudioGraph.performOnMain*`, MainAudioGraph.swift:1543–1619):
- `processTick` :1580 and :1587 → `syncAudioInputRouting(for:)` (:2561) →
  `mainAudioGraph.syncAudioInputRoutings` (MainAudioGraph.swift:264).
- `processTick` :1586 → `scheduleActiveAudioInputLoopPlayback()` (:2594) →
  `mainAudioGraph.scheduleAudioInputLoopPlayback` (MainAudioGraph.swift:363).

**Evidence — main → tick edges**:
- `EngineController.stop()` :564 → `clock.stop()` → `queue.sync` (TickClock.swift:69, 102).
- `EngineController.setBPM` :863 → `clock.bpm` setter → `queue.sync` (TickClock.swift:29).
  BPM slider drags hit this repeatedly.
- `clock.isRunning` getter (TickClock.swift:37) — any main-thread caller.
- `shutdown()` :818/:824 → `clock.stop()`.

**Interleaving**: user presses Stop (or drags the BPM control) at the same instant a tick is
in flight that has any audio-input work pending (routing change, failed/first loop schedule,
arm/complete transition). Main joins the tick queue; the tick joins main. Identical shape to
the confirmed `SamplePlaybackEngine` bug fixed by making play fire-and-forget
(SamplePlaybackEngine.swift:610–621 documents that hang).

Note: with **no audio-input track in the project**, `advanceAudioInputScheduling` mutates
nothing and `scheduleActiveAudioInputLoopPlayback` finds no candidates, so no main hop
happens and stop/BPM are safe. The window exists exactly when audio-input features are in
use — matching "it only hangs sometimes".

**Proposed fix**
Make the tick-side graph interactions asynchronous, mirroring the SamplePlaybackEngine fix:
- `scheduleAudioInputLoopPlayback` and `syncAudioInputRoutings` callable as
  `main.async` fire-and-forget from off-main, with the success/failure bookkeeping
  (`scheduledLoopPlaybackID`, retry flag) updated from the main-thread closure via the
  existing `updateAudioInputRuntime`-on-main path.
- Alternatively, route all audio-input graph work through a dedicated coalescing "graph
  request" channel drained on main, so the tick queue never blocks on main at all.

---

#### D3. Main↔AudioInstrumentHost-queue AB-BA: preset/state readouts vs per-note `main.sync`

**Evidence**
- Host queue → main (sync): `AudioInstrumentHost.play` dispatches on its own queue and then
  calls `performOnMain` (= `DispatchQueue.main.sync`, AudioInstrumentHost.swift:72) for
  **every note-on** (:398) and schedules a `queue.asyncAfter` note-off that also does
  `performOnMain` (:406). `shutdown` (:208), `stopAllNotes` (:434) likewise.
- Main → host queue (sync): `captureStateBlob` (:308), `presetReadout` (:323),
  `loadPreset` (:350) are `queue.sync`, and are called from main by the preset browser UI
  (TrackDestinationEditor.swift:394, 481, 661, 664 via EngineController.swift:1350, 1360).

**Interleaving**: an AU-instrument track is playing (so the host queue continuously contains
items that `main.sync`); the user opens the preset browser or loads a preset. Main enters
`queue.sync` and parks behind a host-queue item; that item parks in `main.sync`. Hang.
Note-offs ride `queue.asyncAfter`, so the host queue has pending main-hopping work even
*after* the last note-on — the window is wide.

**Proposed fix**
Either side breaks the cycle; safest is both:
- Replace the host's per-note `performOnMain` with `main.async` (note timing already
  tolerates queue latency — the note-off is timer-scheduled), or send MIDI to the AU via
  `scheduleMIDIEventBlock` without a main hop at all.
- Make `presetReadout`/`captureStateBlob`/`loadPreset` async with completion handlers, or
  have them snapshot the needed AU references under `snapshotLock` instead of joining the
  serial queue.

---

#### D4. `@Observable` `audioInputRuntimeRevision` written **on the tick queue** (class-1 variant, missed by the fix that introduced the rule)

**Evidence**
- `updateAudioInputRuntime` bumps `audioInputRuntimeRevision &+= 1` directly on the calling
  thread (EngineController.swift:2857–2864). The comment explains the bump must be outside
  `stateLock` — but not that it must be on main.
- It *is* called from the tick queue: `scheduleActiveAudioInputLoopPlayback` (:2618–2621),
  which runs in `processTick`.
- Contrast the sibling path that got it right: `advanceAudioInputScheduling` (:2636–2646)
  routes the *same* revision bump through `publishToMain` "because this runs from the tick
  queue".
- `audioInputRuntimeRevision` is **not** `@ObservationIgnored` (:135) and is read by SwiftUI
  through `audioInputRuntime(for:)` (:628).

**Interleaving**: tick queue successfully schedules a loop buffer → bumps the observable on
the tick thread → Observation's `willSet` runs registered observer callbacks synchronously on
the tick thread; SwiftUI's tracking can re-enter main-side state. If main is at that moment
parked in `clock.stop()`'s `queue.sync` (or in `stateLock`), this is the exact
runtime-confirmed deadlock class fixed twice before. Even absent the deadlock, an off-main
unsynchronized write to `@Observable` storage is a data race against main-thread reads.

**Proposed fix**: inside `updateAudioInputRuntime`, do the bump via `publishToMain` (it
already runs inline when on main, preserving the synchronous test-driver behavior the
comment relies on).

---

### DATA RACE

---

#### R1. `currentDocumentModel` read on the tick queue, mutated in place on main, no shared lock

**Evidence**
- Tick-queue reads: `processTick` :1580 and :1587 pass `currentDocumentModel` to
  `syncAudioInputRouting(for:)`, which iterates `documentModel.tracks` in
  `audioInputRoutingRequests(for:)` (:2571–2588) and computes
  `Self.effectiveMixerMuteState(for:)` over the whole project.
- Main-thread in-place mutations with no lock: `writeStateBlob` (:1119), `setMix` (:1144),
  `setMixerBusMix` (:1158), `setMixerBusParameters` (:1167), `apply(sendBus:)` (:1179),
  and the wholesale `currentDocumentModel = documentModel` in `apply(documentModel:)` (:908)
  — `documentApplyLock` only serializes `apply` against itself; tick readers never take it.
- The header comment ":2077 `currentDocumentModel` is not read on the tick path" is **false**
  for the audio-input branch.

**Impact**: `Project` is a CoW struct of arrays/dictionaries; concurrent read during in-place
element mutation is a Swift exclusivity violation — torn track arrays, spurious CoW copies of
partially-written state, or a crash (most likely during fader drags while an audio-input
track is live).

**Proposed fix**: the tick path should consume a published immutable snapshot. Either reuse
`tickState.currentPlaybackSnapshot()` (extend `PlaybackSnapshot` with the few fields
`audioInputRoutingRequests` needs: tracks' `outputBusID`, mix, mute topology), or keep an
`AudioInputRoutingInputs` value updated under `stateLock` whenever the document changes.

---

#### R2. `chordContextByLane` — reader locks, writer doesn't

**Evidence**
- Read **under `stateLock`** on the tick queue: `prepareTick` :1610–1620 (`self.chordContextByLane`
  inside the `withStateLock` tuple read).
- Written on **main with no lock**: `dispatchTick`'s `.chordContextBroadcast` case publishes via
  `publishToMain { self?.chordContextByLane[lane] = chord }` (:1858–1861).

A lock taken on only one side of a read/write pair synchronizes nothing: the tick queue can
read the `[String: Chord]` dictionary mid-mutation. (Main-thread *observation* of the
property is fine; the cross-thread read is not.)

**Proposed fix**: keep an `@ObservationIgnored` engine-side copy guarded by `stateLock`
(written inside the lock from the same `publishToMain` closure or directly at dispatch time),
and let the `@Observable` property be a main-only mirror.

---

#### R3. `AudioInputCaptureSummaryRing` seqlock has no writer-side "dirty" marker — the re-check can pass on a torn slot

**Evidence**: AudioInputCaptureStore.swift:255–296. Writer order is: claim sequence →
**write payload** → `slot.sequence.store(sequence)`. The reader copies `trackID`/`packet`
then re-checks `slot.sequence.load() == nextSequence` (:290). A *lapping* writer
(sequence `n + 1024`) that is mid-payload-write has not yet stored its sequence, so the
slot still reads `n` and the re-check **passes on a torn copy**.

**Impact**: low — payload is POD (floats, ints, UUID), consumer is meter/progress bookkeeping;
requires the drain to lag a full 1024-slot lap. Still a genuine race the seqlock comment
claims to exclude, and formally UB in Swift.

**Proposed fix**: standard two-phase seqlock — writer stores a sentinel
(`slot.sequence.store(-sequence)` or `sequence - capacity`) *before* writing the payload,
then the real sequence after; reader treats the sentinel as "skip ahead". Or check
`writeSequence.load() - nextSequence < capacity` after copying.

---

### BENIGN-BUT-FRAGILE

---

#### B1. Self-healing loop-playback retry has no backoff and can rebuild the graph every tick

**Evidence**: `processTick` :1582–1588 retries `scheduleActiveAudioInputLoopPlayback()`
every tick by design (comment documents the silent-buffer bug it fixes). Failure modes:
- `play()` throws → host forced `.silent` (MainAudioGraph.swift:409–411) → the next
  `syncAudioInputRoutings` fails `canUpdateAudioInputRoutingParametersOnMain` (source
  mismatch) → **full rebuild**: `engine.stop()`, teardown/reinstall, retap, `engine.start()`
  (MainAudioGraph.swift:277–305). If the player keeps failing (wedged device), this is an
  engine stop/start + tap churn every ~31 ms, on main, while UI reads the graph.
- Buffer conversion failure (:384–390) returns false *without* silencing → per-tick loop of
  publication-queue sync + `main.sync` schedule attempt + `main.sync` routing sync, forever
  (the candidate never clears because `scheduledLoopPlaybackID != recordedLoopID` persists).

**Impact**: audible dropouts, stuck meters (taps removed/reinstalled), main-thread churn, and
every retry is another D2 deadlock window. Not re-entrant (all on the tick queue serially),
but unbounded.

**Proposed fix**: cap or back off retries (e.g. retry on the next bar, not the next tick;
give up after N failures and surface route state `.silentUnavailable`), and treat a
conversion-impossible buffer as terminal (clear `recordedLoopID`/mark unschedulable) instead
of retrying an operation that cannot succeed.

---

#### B2. CoreAudio HAL calls under `stateLock`

**Evidence**: `syncAudioInputRuntimes` computes `audioInputRouteState(for:)` *inside*
`withStateLock` (EngineController.swift:2533–2554, calls at :2541/:2545) →
`mainAudioGraph.availableInputChannelCount` → `engine.inputNode.inputFormat(forBus: 0)`
(MainAudioGraph.swift:259–262). Same inside `refreshAudioInputRouteStates`'s
`updateAudioInputRuntime` closure (:620–622). The repo's own memory notes document HAL calls
stalling for minutes; a stalled `inputFormat` here pins `stateLock` on main, which freezes
`prepareTick` (it takes `stateLock` first thing, :1610) — playback stops and every UI read
of engine state hangs behind it.

**Proposed fix**: read the channel count once outside the lock and pass it in
(`Self.audioInputRouteState(for:availableChannelCount:)` already exists for exactly this
shape — :2933).

---

#### B3. Spin-waits reachable while holding `stateLock`

**Evidence**:
- `AudioInputCapturePCMWriterSlot.install` spins `Thread.sleep(0)` until tap readers drain
  (AudioInputCaptureStore.swift:223–227); called *inside* the `withStateLock` closure from
  `cancelAudioInputArm` (:716) and `markAudioInputLoopPlaceholder` (:784).
- `AudioInputCapturePCMWriter.materializeCapturedPCM` spins on in-flight copies (:184–188);
  reached from `completeAudioInputCapture` while the tick queue holds `stateLock` **and**
  the publication queue **and** the store lock (:2769–2775 → :390).

Today the wait is bounded by one tap callback (~µs) so it's benign, but it couples three
lock levels to the audio thread's progress. If a tap ever blocks (e.g. on the meter bank
lock or a future allocation), this becomes a multi-queue stall.

**Proposed fix**: hoist `install(nil)` outside the locked closures (it has no runtime-state
dependency); document the spin bound on the writer.

---

#### B4. Master-render file IO on the tap callback thread

**Evidence**: master meter tap closure (MainAudioGraph.swift:982–986) →
`writeMasterRenderBufferIfActive` → `AVAudioFile.write` (:959–969) under `masterRenderLock`,
which main also takes in `startMasterRender`/`stopMasterRender` (:925, :942). Blocking disk
IO on the tap dispatch queue can back the tap up (dropped meter buffers) and briefly blocks
main's start/stop on the lock. Acceptable by design (documented), but worth keeping off any
future render-thread path.

---

#### B5. `AudioEffectChoiceCache.cachedChoices` can block main on a semaphore for the AU scan

**Evidence**: AudioEffectChoice.swift:109–146 — if the cache is `warming`, the caller does
`semaphore.wait()` with no timeout; the warm scan runs on a global queue and can take
seconds (AU component enumeration). A main-thread caller freezes the UI for the scan
duration; > `maxWaiters` (64) concurrent waiters would never be signaled.

**Proposed fix**: return `[]`/`nil` when warming and notify via callback, or use
`DispatchGroup`/continuation rather than a counted-signal semaphore.

---

#### B6. `SamplePlaybackEngine.cachedFile` opens `AVAudioFile` on the tick queue under `lifecycleLock`

**Evidence**: SamplePlaybackEngine.swift:491–501, called from `play`/`playSlice` on the tick
queue (:181, :206). `lifecycleLock` is contended by main (`prepareTrack`, `setTrackMix`, …),
so a slow disk open delays both the tick and main-side mixer updates. Also the whole 64-entry
cache is dropped at once (:496), causing reopen storms. Fragile, not a cycle
(`lifecycleLock → graphLock` ordering is consistent; nothing takes them in reverse).

---

#### B7. `AtomicInt64`/`AtomicInt32` are built on deprecated `OSAtomic*Barrier`

**Evidence**: AtomicInt.swift. Semantically correct (full barriers; `store` is a CAS loop),
but deprecated since macOS 10.12 and needlessly expensive. Migrate to Swift `Atomics`
(`ManagedAtomic`) when convenient; no behavioral bug today.

---

## 3. Patterns that are SOUND — do not "fix" these

- **`publishToMain` discipline** (EngineController.swift:165–181): all transport/phrase/
  capture `@Observable` publication hops to main (inline when already on main so synchronous
  test drivers still observe writes). The hop is the load-bearing part — see D4 for the one
  caller that bypasses it.
- **Meter pipeline** (`MasterMeterPublisher` + `MasterMeterTransport` + `ChannelMeterBank`):
  tap threads touch only atomics (`storeMaximum`/`exchange`, MainAudioGraph.swift:1862–1907);
  a single main-queue timer pumps publishers **outside** the bank lock
  (ChannelMeterBank.swift:85–100); `displayState` writes happen on main with no locks held
  and skip no-op assignments (:1780). The bank's "publishes outside locks" claim **verifies**.
- **`SamplePlaybackEngine.playWithPreparedVoice` off-main → `main.async` fire-and-forget**
  (SamplePlaybackEngine.swift:600–622) — the confirmed class-2 fix; timing rides the
  scheduled `AVAudioTime`. Do not make this sync again.
- **`TickStateBuffer`**: pure copy-in/copy-out under a private lock; never runs callbacks or
  foreign code under the lock (TickStateBuffer.swift).
- **`TickClock.syncOnQueue`** queue-specific-key re-entrancy guard (TickClock.swift:97–103)
  and `readAudioInputCaptureStore`'s identical guard (EngineController.swift:2320–2329) —
  prevent self-deadlock on re-entrant calls.
- **Tap generation tokens** (`masterMeterTapGeneration`, `channelMeterTapGeneration`,
  `captureTapGeneration`): stale tap closures self-neutralize by comparing an atomic
  generation — correct lock-free pattern.
- **ObjC exception catcher around `AVAudioPlayerNode` start/schedule and `installTap`**
  (`SEQRunCatchingObjCException` + `isNodePlayableNow` pre-check): the check-then-act race
  is known and *accepted* because the catcher makes the loser drop a trigger instead of
  crashing (SamplePlaybackEngine.swift:231–248, MainAudioGraph.swift:391–413, 1075). No
  unguarded equivalents were found: every `play()`/`scheduleBuffer` on a possibly-stale node
  goes through the catcher.
- **`graphLock` acquired only inside `performOnMain` closures** — the comment at every site
  ("holding graphLock across DispatchQueue.main.sync is a lock-order deadlock waiting to
  happen") is honored everywhere in `MainAudioGraph`.
- **`AudioInputCapturePCMWriterSlot` / `AudioInputCapturePCMWriter`**: reserve-by-CAS frame
  ranges, in-flight reader/copy counters, deactivate-then-drain before materialize; the slot
  keeps the old writer retained until readers drain, so `takeUnretainedValue` is safe.
- **`stepOrderToggleAppliedHandler`** hops to main *async* in the session
  (SequencerDocumentSession.swift:117–129) — correct way for a tick-queue callback to mutate
  @MainActor state.
- **`RecordingLibrary`**: file IO on the persistence queue; `register` hops the `@Observable`
  list mutation to main (RecordingLibrary.swift:161–173); take numbering reads sidecars from
  disk rather than the not-yet-updated observable list (:180). Completion hooks in
  `schedulePersistCapturedRecording` resolve name/BPM on main first, write on the utility
  queue, and publish results back on main (EngineController.swift:2799–2843). Sound.
- **Lock ordering `stateLock → publicationQueue`** is consistent on both main and tick;
  the publication queue never syncs back into `stateLock` (its drain publishes via
  `publishToMain` async). Preserve this: never add a `publicationQueue.sync`-from-inside
  path that takes `stateLock`… and never add a `stateLock` acquisition inside the drain.
- **`reconcileNoteRepeats`** deliberately copies keys out of `stateLock` before calling code
  that takes `phraseNavigationLock` (comment at EngineController.swift:3450) — keeps the two
  locks unordered. Keep it that way.
- **`SessionSnapshotPublisher` / `SequencerDocumentSession`** are `@MainActor`; the engine's
  snapshot copy is a separate object under `TickStateBuffer`'s lock. The "two copies, one per
  thread-domain" split is intentional (documented in SessionSnapshotPublisher.swift:13–14).

---

## 4. Mapping to user-visible symptoms

| Symptom | Most likely finding |
|---|---|
| **Whole-app hang pressing Stop / dragging BPM while an audio-input track is armed, recording, or buffer-monitoring** | D2 (and D1 at the record-start bar boundary) |
| **Whole-app hang the moment recording begins (bar boundary) with the input panel visible** | D1 (UI reads `withStateLock` at meter rate while tick holds `stateLock` and `main.sync`s) |
| **Hang opening the instrument preset browser / loading a preset while notes play** | D3 |
| **Hang on Stop with no audio-input involvement** | D4 (observable written on tick thread while main is parked in `clock.stop()`) |
| **Crash or corrupted track state during fader drags while audio-input is live** | R1 |
| **Audible dropouts / engine restarts / stuck or flickering meters during buffer-monitor** | B1 (per-tick full graph rebuild storm) |
| **Multi-second UI freeze on device switch or first audio-input use** | B2 (HAL under `stateLock` freezes tick + UI), plus the already-documented HAL stalls |
| **UI freeze opening an effect picker for the first time** | B5 |
| **Laggy step entry / controls during dense sample playback** | B6 (disk IO under `lifecycleLock` on the tick path) |
| **Briefly wrong/garbage input level or progress** | R3 (rare), B1 |

---

## 5. Summary counts

- **Deadlock-possible: 4** (D1–D4)
- **Data race: 3** (R1–R3)
- **Benign-but-fragile: 7** (B1–B7)

Scariest single finding: **D1** — the tick queue performs `DispatchQueue.main.sync`
(`audioInputCaptureFormat`) while holding `stateLock`, so the instant recording begins at a
bar boundary, any concurrent main-thread `withStateLock` read (which the input panel does at
meter rate) deadlocks the entire app with no recovery.
