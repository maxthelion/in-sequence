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
