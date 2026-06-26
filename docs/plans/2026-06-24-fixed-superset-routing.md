# Plan: Fixed-Superset Audio Routing

**Status:** Proposed — 2026-06-24
**Goal:** Eliminate live engine stop/start and live node create/teardown during
playback. Make every routing change — scene A/B crossfade, track send levels,
per-track bus selection, mute/fill, insert enable — a **gain ramp or `bypass`
toggle on an always-connected graph**. This is guardrail rule 5
([architecture-guardrails.md → Audio Engine Hard Rules](/Users/maxwilliams/dev/in-sequence/wiki/pages/architecture-guardrails.md)).
**Unblocks:** click-free scene transitions, the per-track A / A+B / B scene-send
selector, and removes the audible gap on track add/route changes.

## Why now

Today routing is implemented as live graph surgery:

- **`connectTrackOutput` (`MainAudioGraph.swift:784`) unconditionally
  `engine.stop()` → rewire → `engine.start()` (`:796-811`)** — an audible gap
  every time a track's output bus changes.
- **`installSendBuses` (`:709`)** has a value-only fast path (`:735-740`, good)
  but still `engine.stop()/start()` on any topology change (`:742-763`).
  **`installMixerBuses` (`:629`)** does the same.
- **`setTrackSendLevels` (`:950`)** updates `outputVolume` in place for the
  common case (`:977-978`, good) **but tears down / recreates the send nodes
  whenever a track crosses between "no active sends" and "some sends"**
  (`:971-974` → `reconnectTrackOutputOnMain`). So a send fader passing through 0
  triggers a live `disconnect`/`detach`/`attach` (`:1644-1709`).
- **`reconnectTrackOutputOnMain` (`:1617`)** creates and `detach`es the
  `fanout`/`sendA`/`sendB` nodes on demand, and the **dry-path geometry depends
  on `engine.isRunning`** (`routesDryThroughFanout = engine.isRunning`, `:1668`)
  — i.e. the wiring is different while playing vs stopped.

The product's identity (live scene crossfading + frequent routing edits) is
exactly the workload this punishes.

## The target shape

**Pre-provision the superset once; change only gains and `bypass` thereafter.**

- Per track, the `fanout → {dryDestination, sendA, sendB}` nodes are attached
  **once when the track is created** and stay connected for the track's life.
  "No sends" is `sendA.outputVolume = 0` / `sendB.outputVolume = 0`, **not** a
  teardown.
- The A and B scene buses, the send-bus destinations, and a fixed pool of mixer
  bus slots are always present. "Adding" a bus/send is claiming a pre-wired slot
  and ramping its gain, never restructuring the running graph.
- Geometry is **independent of `engine.isRunning`** — one wiring, always.
- The only true live graph edits left are genuinely additive (a new track's
  nodes, a pooled drum part) and are done while the new branch is at gain 0,
  then ramped in. Nothing that is *currently sounding* is ever disconnected;
  ramp to silence first, cut on silence.
- All crossfades/level changes are **equal-power gain ramps, ~5–15 ms**, not
  stepped writes.

## Phases

### R0 — Persistent per-track send nodes (kills the zero-send teardown)

- Attach `fanout`/`sendA`/`sendB` per track once (at track-create / first
  route), wired to `[dryDestination, sendA-bus, sendB-bus]`, and keep them.
- `setTrackSendLevels` becomes **only** `sendA.outputVolume`/`sendB.outputVolume`
  ramps. Delete the `hasSendNodes != hasActiveSends` reconnect branch
  (`:971-974`) and the create/teardown in `reconnectTrackOutputOnMain`
  (`:1644-1709`).
- Make `routesDryThroughFanout` constant (always route dry through the fanout);
  remove the `engine.isRunning` dependence (`:1668`).
- **Acceptance:** `setTrackSendLevels` at any value, including crossing 0,
  performs zero `reconnectTrackOutput` (assert `reconnectTrackOutputCountForTesting`
  unchanged across a 1→0→1 send sweep), zero `engine.stop()`, zero `detach` of a
  live node. A send sweep through 0 is click-free (offline-render amplitude
  continuity check).

### R1 — No engine stop/start for track output routing

- `connectTrackOutput` (`:784`): for a **new** track, attach + connect its
  (silent) nodes on the running engine, then ramp in — no stop/start. For a
  **bus reassignment**, ramp the track to silence, reconnect to the new bus,
  ramp back — no stop/start.
- **Acceptance:** adding a track and changing its output bus during playback do
  not call `engine.stop()` (assert), and produce no audible gap (offline check).

### R2 — Sends/mixer-bus topology without full-engine restart

- `installSendBuses` (`:709`) / `installMixerBuses` (`:629`): pre-provision a
  fixed number of bus slots so changing send/insert *content* is gain + `bypass`
  + per-slot rebuild, never a whole-engine stop. For a genuine new-node case,
  build the sub-graph and crossfade it in rather than `engine.stop()`.
- Widen the existing value-only fast path (`:735-740`) to cover insert
  enable/disable via `AVAudioUnit.bypass` instead of topology rebuild.
- **Acceptance:** `sendBusTopologyInstallCountForTesting` /
  `installMixerBuses` no longer trigger `engine.stop()` for in-place content
  changes; only a genuinely new bus slot does any structural work, and it
  crossfades.

### R3 — Drum-part node pool (the one genuinely dynamic case)

- Pre-attach a pool of part voice/instrument slots; "add part" claims a slot and
  ramps its send up from 0; "remove part" ramps to 0, returns to pool, defers
  the disconnect (or leaves it muted). Per-part routing = changing which
  always-connected destinations its gains target.
- **Acceptance:** add/remove a drum part during playback with no `engine.stop()`
  and no disconnect of a sounding node.

#### R3 verification (2026-06-26): a dedicated node pool is NOT needed — VERDICT

R3 was written before R0–R2, the deadlock root-fix (lifecycleLock made a leaf
lock), ramp-before-disconnect, and the live-safe reconnect landed. With those in
place the dedicated pre-attached part-voice pool is **unnecessary**: drum-part
add/remove during playback already flows through the unified, hang-safe,
live-safe structural path, and Hard Rule 5's "pre-attached node pool" intent is
satisfied-in-spirit by that path.

What the path actually is (a drum part is a standalone `StepSequenceTrack` with a
`groupID`, not a sub-object — see `TrackGroup.memberIDs`):

- Add/remove a part → `SequencerDocumentSession.addDrumPart` / `removeDrumPart`
  (`Sources/App/SequencerDocumentSession+Mutations.swift`) → `batch(impact:
  .fullEngineApply)` → `EngineController.apply(documentModel:)`. Because
  `pipelineShape` is one entry per track
  (`EngineControllerRoutingHelpers.swift:34`), a part add/remove changes the shape
  and routes to `buildPipeline` → `applyBroadSync`. `buildPipeline` rebuilds only
  the **note-generation `Executor`** (not the AVAudioEngine graph) and calls
  `syncAudioOutputs` / `installMixerBuses`; it does **not** `engine.stop()/start()`.
- The actual audio nodes for a sample/slicer part are managed by
  `SamplePlaybackEngine.prepareTrack` / `removeTrack`
  (`Sources/Audio/SamplePlaybackEngine.swift`). `removeTrack` first drops the
  track from every tick-path dictionary **under the leaf `lifecycleLock`** (so the
  tick path can never select its voices again), then detaches the captured nodes
  **outside the lock** — i.e. no lock held across a live `engine.disconnect`/
  `detach` (the old deadlock shape), and the node is removed from the trigger
  selection before teardown so nothing new schedules onto it.

**Ramp-before-detach fix (2026-06-26 adversarial review).** The first pass of this
verification was caught hard-cutting on **removal**: `removeTrack` /
`teardownTrackVoicePool` / `teardownBusVoicePool` detached a potentially-sounding
node with **no gain ramp** — the exact click Hard Rule 5's "ramp to silence first"
clause forbids (the codebase's `withTrackGainRampedToSilence` was wired for FX
inserts / AU host / audio-input routes but *not* for sample-track teardown). Fixed
for the **removal** path: `removeTrack` now ramps the track's output chokepoint(s)
— the track mixer (non-bus) or the bus-voice mixers (bus-routed) — to silence via
`MixerGainRamp`, detaching only on ramp completion (`rampMixersToSilenceThenDetach`).
The dictionary removal still runs synchronously under the lock, so engine-truth
readbacks (`trackAppliedOutputGainForTesting`, the rig's
`EngineConnectedMemberCount`) drop immediately; only the physical node detach is
deferred ~12 ms behind the fade. Covered by
`RampBeforeDisconnectTests.test_removeTrack_soundingSampleTrack_rampsChokepointToSilenceBeforeDetach`
(asserts the ramp path is taken and the chokepoint reaches 0 before detach).

**Known residual — route-switch teardown still hard-cuts.** The same hard-cut
shape also lives in the two *route-switch* teardowns (`setTrackOutputBus`'s
bus→master `.teardownBus` branch and `prepareBusVoicePool`'s stale / master→bus
teardown). Applying the same defer-detach-behind-a-ramp there **regressed
route-to-master to silence** (the rig caught it: `routeTrack-1-to-master` stayed
silent for the full poll) — the route-switch *rebuild* depends on the old pool
being torn down synchronously *before* `prepareTrack` rebuilds, so a naïve defer
breaks it. Reverted to the original synchronous teardown. A correct fix needs a
real crossfade (ramp the outgoing nodes to silence while preserving teardown→rebuild
ordering), which is more than R3's scope. Filed as
`docs/bugs/20260626-route-switch-teardown-hard-cut/`. Removal (drum-part / track
delete) is the common, now-fixed case; route-switch hard-cut clicks remain on the
backlog.

Evidence — routing-stress rig PASS 3 (real HAL, headless, sample-only fixture),
`scripts/visual-scenarios/routing-stress.sh`: during playback, on the "Audio Rich
Kit" group, it adds 2 sample-backed sounding parts, then removes the added parts
AND an original sounding member (the Snare), interleaved with the sounding drum
bed. Result: **HANG=0, CRASH=0, SILENCE=0, CLICK=0, POSTFAIL=0** with engine-truth
post-conditions: the group's engine-connected member count tracks the document
member count after every edit (added part's sample mixer node attached; removed
part's node gone), and the newly-added part is acoustically audible. New command
keys: `drumGroupAddPart=<groupIdx>:<sampleSourceTrackIdx>` and
`drumGroupRemovePart=<groupIdx>:<memberIdx>` in
`Sources/UI/VisualScenarioCommandRunner.swift`; new status readbacks
`drumGroup<N>MemberCount` / `drumGroup<N>EngineConnectedMemberCount`.

Honest limits (from the adversarial review + the rig's standing caveats):
- **Destination coverage.** The rig only exercises `.sample` parts. A real drum
  part's destination (`Project.defaultDestination`) can also be `.internalSampler`
  (silent/unimplemented fallback), `.inheritGroup` (shared AU/MIDI host), or
  `.auInstrument`/`.midi` — these fall into `syncSampleMixers`'s `default: continue`
  and take entirely different sync paths (`syncAudioOutputs` / `syncMidiOutputs`).
  Their live add/remove safety is **not** proven here; AU needs a human-granted TCC
  session and cannot be exercised unattended. The `.inheritGroup` shared-host case
  also intersects the open AU group-member mute decision
  (`docs/human-attention/DECISION-au-group-member-mute.md`).
- **Add has no current UI counterpart.** There is no app affordance to add a
  single part to an already-playing group — groups are created atomically via
  `addDrumGroup` (the in-memory `DrumGroupPlan` is committed in one shot). The
  rig's `addDrumPart` is a synthetic live structural add that exercises the same
  `prepareTrack` live-attach the real atomic creation uses; part *removal* maps
  cleanly to the real `removeTrack`.
- **Coarse master metrics.** CLICK/SILENCE master metrics are diag-only on the
  noisy drum fixture; per-track audibility + engine-truth membership are the
  gating signals. The added-part audibility check is a permissive (-90 dBFS,
  first-hit) liveness ping, not a rhythmic-correctness check.

Click-freeness of the *removal* is now backed by the ramp-before-detach fix above
(no longer "rests on the ear" for the sample path); the human-ear pass remains the
backstop for the AU / shared-host destinations the rig can't reach.

**Decision:** do NOT build the speculative part-voice pool. R3 is closed as
satisfied by the general live-safe path; keep the new PASS 3 rig coverage as
permanent regression protection. If an AU-drum-part live edit is ever shown to
click/glitch in a human pass, revisit a pool scoped to that case.

### R4 — Per-track scene-send selector: A / A+B / B (the feature)

- UI: a control in the track-detail **audio-out / ROUTING tab** offering
  **A**, **A+B**, **B**. It sets the persistent send gains:
  A → `{sendA:1, sendB:0}`, A+B → `{1,1}`, B → `{0,1}`, ramped.
- Because R0 made the send nodes permanent, this is **pure gain on a fixed
  graph** — no topology change, glitch-free, and it lets the crossfader carry
  genuinely different tracks per side.
- **Home:** the routing-tab UI. The in-flight `feature/routing-source-mixer-split`
  branch reworks exactly this tab (source well + mixer/FX well) but is **UI-only
  and does not touch `MainAudioGraph`**, so it does not collide with R0–R3. Land
  (rebase + close its visual gate) before building the selector UI on top; the
  gain plumbing (R0) is the dependency, not that branch.
- **Acceptance:** selecting A / A+B / B during playback changes only send gains
  (assert no reconnect / no stop), and a track set to A-only contributes nothing
  to B (and vice-versa).

## Enforcement

- **`graph-mutation-conformity` observer** (from the audio adherence set): flags
  `engine.stop()/start()`, `attach`/`detach`/`connect`/`disconnect` tied to
  topology during playback, and any `disconnect` not preceded by a silence ramp.
- **Test:** during playback, a battery of routing edits (send sweep through 0,
  bus reassignment, A/A+B/B toggle, insert enable) asserts `engine.stop()` is
  never called and the relevant `…CountForTesting` reconnect counters stay flat.
- Offline-render amplitude-continuity checks for click-freeness on crossfade /
  send-zero crossings.

## Sequencing

R0 → R1 → R2 → R3, each bounded with its own playback test. R4 (the A/A+B/B
selector) depends only on **R0** (persistent send nodes) for its audio
correctness and on the routing-tab UI for its home — it can land as soon as R0
is in, independent of R2/R3.

## Out of scope

Sample-accurate crossfade timing / custom DSP (would need the `AVAudioSourceNode`
+ C++ core; a click-free equal-power gain ramp does **not** need sample
accuracy). Event-timing sample accuracy is the separate
[sample-accurate timing plan](/Users/maxwilliams/dev/in-sequence/docs/plans/2026-06-24-sample-accurate-timing.md).
