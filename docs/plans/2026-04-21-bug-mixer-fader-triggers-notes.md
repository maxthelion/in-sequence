# Bug: Mixer fader drag triggers unintended notes

**Date reported:** 2026-04-21
**Status:** ✅ Fixed 2026-04-21 by `docs/plans/2026-04-21-fix-mixer-fader-throttle-and-scoped-setmix.md`. Tag `v0.0.24-mixer-fader-throttle`.
**Severity:** High — audible regression that makes the mixer unusable during playback; no data corruption.
**Reporter:** maxwilliams (Max)

## Symptom

While the transport is playing, dragging a level (or pan) fader in the Mixer emits extra, unintended notes — as though the fader gesture is interacting with the main sequencer loop.

## Root cause

Two compounding issues:

1. **UI has no throttling.** `Sources/UI/MixerView.swift:180–181` writes `track.mix.level` on every tick of a `DragGesture(minimumDistance: 0).onChanged`. Pan is a raw `Slider` binding. No `onEditingChanged`, debounce, or drag-end commit — every pixel of mouse motion fires a document mutation.

2. **Each document mutation runs the full engine apply path.** `Sources/UI/ContentView.swift:22–24` `.onChange(of: document.project)` calls `engineController.apply(documentModel:)` for *any* mutation. The apply path has unsynchronized writes that race with the tick thread:
   - `Sources/Engine/EngineController.swift:194` writes `currentDocumentModel = documentModel` on main **without** `withStateLock`.
   - The tick thread's `prepareTick()` captures `audioTrackRuntimes` / `generatorIDsByTrackID` under the lock but uses those captures **after** the lock is released. A fader-driven apply slipping in between capture and use produces a runtime table that doesn't match the `documentModel` snapshot the tick is dispatching against.
   - `Sources/Engine/EngineController.swift:74` `currentLayerSnapshot` is `@ObservationIgnored` and mutated from the tick thread without a lock, yet read from the apply path on main.

The audible effect is not `AudioInstrumentHost.setMix(...)` itself — that is clean. The notes come from the tick mis-dispatching already-scheduled events to the wrong AU / sink while the apply is in flight.

Full diagnostic from the 2026-04-21 audit is in the agent conversation transcript.

## Reproduction

1. Open a document with at least two tracks, at least one of which has an AU instrument destination.
2. Press play.
3. Drag a level fader in the Mixer. Expected: clean level change. Actual: stray notes fire.

## Suggested fix directions (turned into the plan)

The **UI throttle** fix is the no-brainer: the mixer should not drive the full engine apply path at all for mix changes. Two complementary changes:

1. **Bypass `apply(documentModel:)` for mix changes.** Add a scoped, lock-safe `EngineController.setMix(trackID:, mix:)` that writes only to the host's volume/pan and the sample mixer. The UI calls this on every drag-tick; the document itself is committed once on drag-end.
2. **Audit the rest of the UI** for other non-debounced document-mutating gestures that hit `apply(documentModel:)` at per-frame rates (BPM slider, transport, clip step toggles, track parameter sliders).

Engine-side race fixes (locking `apply()` end-to-end, or making the tick use locked snapshots exclusively) are a separate, larger fix — **out of scope here**. Throttling the UI closes the race window to the fast case (no drags means no apply storms) and makes the mixer usable *now*.

## Not in scope for this report

- Fixing the unsynchronized `currentDocumentModel` write and `currentLayerSnapshot` race in `EngineController`. Logged for a later plan. The throttle fix makes the bug impractical to hit but does not remove the underlying race; any future change that reintroduces high-frequency `apply(documentModel:)` calls could expose it again.
- Redesigning `TrackPlaybackSink.setMix` / `SamplePlaybackSink.setTrackMix` signatures. Reuse as-is.

## Next step

Execute `docs/plans/2026-04-21-fix-mixer-fader-throttle-and-scoped-setmix.md`.
