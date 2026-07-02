# Plan: Fixed-Superset Audio Routing

**Status:** Proposed — 2026-06-24
**Goal:** Eliminate live engine stop/start and live node create/teardown during
playback. Make every routing change — scene A/B crossfade, track send levels,
per-track bus selection, mute/fill, insert enable — a **gain ramp or `bypass`
toggle on an always-connected graph**. This is guardrail rule 5
([architecture-guardrails.md → Audio Engine Hard Rules](/Users/maxwilliams/dev/in-sequence/wiki/pages/architecture-guardrails.md)).
**Unblocks:** click-free scene transitions, click-free live send-level changes,
and removes the audible gap on track add/route changes. (The per-track
A / A+B / B "scene-send" selector originally listed here was built and then
REVERTED — see "R4 REVERTED" below.)

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

#### R4 build landed (2026-06-26): ENGINE + MODEL + RIG done; UI DEFERRED

The audio plumbing, model, session mutation, command vocab, and rig coverage for
the A / A+B / B selector are built. **Only the UI selector remains**, and it is
deliberately deferred to the `feature/routing-source-mixer-split` tab rework (see
"Home" above) to avoid a guaranteed merge conflict on the routing tab.

What is now in place (all uncommitted on `audio-routing-cleanup`):

- **Engine — glitch-free live switch.** `MainAudioGraph.setTrackSendLevels`
  (`Sources/Audio/MainAudioGraph.swift`) now RAMPS the steady-state path: when
  the persistent send nodes already exist (the live A/A+B/B switch on a sounding
  track), it applies the new sendA/sendB via `MixerGainRamp.shared.ramp(...)` on
  the send-mixer nodes instead of a hard `outputVolume =` write (which clicked the
  aux bus). The first-time-setup path (send nodes not yet created →
  `reconnectTrackOutputOnMain`) still uses the immediate setup write — nothing is
  sounding through brand-new send nodes, so ramping from a default would be wrong.
  This is pure gain: no attach/detach/connect/disconnect, no engine stop/start, no
  topology change. New counter `sendRampCountForTesting` asserts the ramp path.
- **Model — `SceneSendMode`.** `Sources/Document/SceneSendMode.swift`: enum
  `{ a, ab, b }` with `init?(sendA:sendB:)` (exact-match derivation else nil =
  Custom), `var sendGains` (a→(1,0), ab→(1,1), b→(0,1)), and
  `TrackMixSettings.sceneSendMode`. Pure derivation over the EXISTING persisted
  `sendA`/`sendB` — **no new persisted field.**
- **Session mutation.** `SequencerDocumentSession.setTrackSceneSend(trackID:,
  mode:)` (`Sources/App/SequencerDocumentSession.swift`) writes the preset gains
  through the existing `setTrackSends` live-mix path, so it rides the now-ramped
  apply (mutate live owner → scoped engine update → debounced flush; the
  performance-time-mutation guardrail shape).
- **Command + rig.** Command key `trackSceneSend=<idx>:<a|ab|b>` in
  `VisualScenarioCommandRunner.swift`, plus engine-truth status readbacks
  `track<N>AppliedSendA/B`, `track<N>SceneSendMode`, `reconnectTrackOutputCount`,
  `sendRampCount`. routing-stress.sh PASS 4 toggles a→ab→b→a on a SOUNDING track
  during playback and asserts the exact preset gains, reconnect-count flat, and
  sendRampCount increasing. GATE: PASS.

**The exact remaining UI step (do it on the split-tab branch):** add a segmented
`Picker` over `SceneSendMode.allCases` (labels "A" / "A+B" / "B"), bound to
`track.mix.sceneSendMode` (show no selection when it is `nil` / Custom), whose
`onChange`/selection action calls `session.setTrackSceneSend(trackID: track.id,
mode: selected)`. Place it in the **mixer/FX well** of the new split routing tab
(the rework target, `Sources/UI/TrackSource/TrackRoutingTabContent.swift`). No
engine, model, or session work is needed — only this view + binding.

**Adversarial-review fixes (2026-06-26):**
- *Ramp-vs-reconnect race (fixed).* The direct `outputVolume` writes in
  `MainAudioGraph.sendNodes` (the reconnect path: bus reroute / FX-insert edit /
  bus reinstall) did NOT bump `MixerGainRamp`'s per-node generation token, so a
  reconnect firing during an in-flight steady-state send ramp could be clobbered
  by the stale ramp landing its old target — the same "deferred path overwrites
  the latest intent" class as the route-teardown bug. Those writes now go through
  `MixerGainRamp.setImmediate` (bumps the generation, cancels any in-flight ramp,
  writes the authoritative value at once).
- *Scope: audio-input tracks are out of the R4 ramp.* An audio-input track's send
  change does NOT take the steady-state send ramp — it fails the equality guard in
  `applyAudioInputRoutingParametersOnMain` and takes `withTrackGainRampedToSilence`
  + full reconnect (the heavier monitor-safe path). So "glitch-free A/A+B/B" is
  proven for **sample/AU** tracks; audio-input send switching rides the existing
  reconnect-with-output-ramp and is a human-tier (mic-permission) check anyway.
- *Pre-existing red test (NOT R4).* `SamplePlaybackEngineFilterWiringTests`
  `test_sampleTrackSendTapRoutesAfterSamplerFilter` /
  `test_trackFilterRoutesToInjectedGraphPreMaster` fail on the clean baseline
  (verified): the first throws `XCTUnwrap` on `engine.filterNode(for:)` returning
  nil at line ~90, *before* any send/gain assertion — unrelated to the R4 ramp.
  When that pre-existing wiring issue is fixed, its synchronous send-gain read
  (line ~99, accuracy 0.0001) will also need the `waitForSendGains`-style poll the
  other two MainAudioGraphTests now use (the send change ramps).

#### R4 REVERTED (2026-07-02): scene-send selector removed — it conflated two features

R4 as specified above was a category error and has been removed (the selector UI,
`SceneSendMode`, `setTrackSceneSend`, the `trackSceneSend=` command vocab and
`track<N>SceneSendMode` status key). What it actually did was preset the two
per-track **FX-return send gains** (`TrackMixSettings.sendA`/`sendB` → the fixed
`SendBusID.sendA`/`.sendB` return strips, per
[mixer-grammar](/Users/maxwilliams/dev/in-sequence/wiki/pages/mixer-grammar.md)) while **labelling** itself a master-scene
selector. It never touched the real scene model (`MasterBusState.scenes` /
`abSelection`), and `MasterBusHost` has no per-track scene-membership gain at all
— every track feeds every scene branch equally. So the control (a) silently
stomped whatever Send A/B aux levels the user had dialed in, and (b) did not do
what its own label claimed.

**Do not reuse `sendA`/`sendB` for scene selection again.** "Which master scene
a track feeds" is the still-**deferred** roadmap item 25,
[docs/roadmap/selective-scene-inputs/](/Users/maxwilliams/dev/in-sequence/docs/roadmap/selective-scene-inputs/README.md) — it needs its own persisted
per-track scene-membership model plus `MasterBusHost` render-branch gain wiring
(Hard Rule 5 review), gated on explicit user reactivation. Send A/B remain plain,
independent FX-return sends.

**What survives from the R4 build (still in place, still load-bearing):**
- The engine work: `MainAudioGraph.setTrackSendLevels` steady-state RAMP path +
  `sendRampCountForTesting` + the `MixerGainRamp.setImmediate` reconnect-race fix.
  Ordinary Send A/B knob drags and `setTrackSends` ride it.
- Rig coverage: routing-stress.sh PASS 4 now drives the same on/off send-gain
  corner set via the plain `trackSend=` vocab (exact applied gains, reconnect
  count flat, sendRampCount increasing) — the guarantee is kept, the scene
  framing is gone. `RoutingNoStopNoReconnectTests` likewise keeps the send A/B
  combination sweep.

## Enforcement

- **`graph-mutation-conformity` observer** (from the audio adherence set): flags
  `engine.stop()/start()`, `attach`/`detach`/`connect`/`disconnect` tied to
  topology during playback, and any `disconnect` not preceded by a silence ramp.
- **Test:** during playback, a battery of routing edits (send sweep through 0,
  bus reassignment, send A/B combination sweep, insert enable) asserts
  `engine.stop()` is never called and the relevant `…CountForTesting` reconnect
  counters stay flat.
- Offline-render amplitude-continuity checks for click-freeness on crossfade /
  send-zero crossings.

## Sequencing

R0 → R1 → R2 → R3, each bounded with its own playback test. R4 (the A/A+B/B
selector) depended only on **R0** (persistent send nodes) for its audio
correctness — it landed after R0 and was later REVERTED as a feature conflation
(see "R4 REVERTED" above); its engine-side ramp work remains.

## Out of scope

Sample-accurate crossfade timing / custom DSP (would need the `AVAudioSourceNode`
+ C++ core; a click-free equal-power gain ramp does **not** need sample
accuracy). Event-timing sample accuracy is the separate
[sample-accurate timing plan](/Users/maxwilliams/dev/in-sequence/docs/plans/2026-06-24-sample-accurate-timing.md).
