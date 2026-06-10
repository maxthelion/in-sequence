# Deep dive: duplicate code paths, potential bugs, race conditions

Date: 2026-06-10. Four parallel audits (duplicates, races, bugs, dead code)
over `Sources/`, findings hand-verified before acting. Items marked **FIXED**
landed today; the rest are a prioritized backlog.

## Fixed today

1. **Debounce cancel fell through to an immediate flush** — FIXED.
   `SequencerDocumentSession.scheduleFlushToDocument` used
   `try? await Task.sleep(...)`, which swallows `CancellationError`; a
   cancelled debounce task therefore woke instantly and called
   `flushToDocumentSync()`. Net effect: during any rapid mutation stream
   (knob drag, slider gesture), *every* re-edit triggered a full
   `exportToProject` immediately — one document export per gesture event,
   precisely the document-write hot path the architecture forbids. Now
   guarded with `Task.isCancelled`; regression test
   `test_cancelledDebounceTask_doesNotFlushEarly`.
2. **Document with empty `tracks` array crashed on load** —
   `Project.normalize` did `tracks[0].id`. FIXED: decode falls back to one
   default track (`test_decode_with_empty_tracks_array_falls_back_to_default_track`).
   (The companion claim about `resolvedPhrases[0]` was a false positive — a
   guard already synthesizes a default phrase.)
3. **Unknown `AudioInputChannel` value failed the whole document decode** —
   the custom decoder threw on unrecognized legacy strings/modes. FIXED:
   unknown values decode as the stereo default; one corrupt channel setting
   can no longer brick a document.
4. **Dead code: `effectivePlaybackSummary`** — orphaned by the phrase-panel
   removal; property, builder, and its two test assertions deleted.

## Backlog — engine threading (needs a focused slice, not drive-by fixes)

These share one root cause: `EngineController` mixes a tick-clock queue,
the main actor, and audio render threads over plain properties guarded by
an inconsistently-applied `stateLock`.

5. **`transportTickIndex` torn/stale reads** (HIGH). Written from the tick
   queue (published to main asynchronously), read without the lock by
   `nextAudioInputPhraseBoundary`, `estimatedPlaybackPhraseAndStep`, and
   `engageNoteRepeat` (reads it *inside* `withStateLock`, but the writer
   doesn't hold that lock). Consequence: arm-quantization and note-repeat
   anchors can capture an off-by-one tick. Fix shape: make it an atomic, or
   route all reads through one locked accessor.
6. **Note-repeat dictionaries** (`activeNoteRepeatsByTrackID`,
   `currentNoteRepeatCapturesByTrackID`) are mostly locked but values escape
   the lock as captures into the prepare path (MEDIUM-HIGH). Audit each
   escape; prefer snapshot-copy-out under lock.
7. **`graphLock` held across `performOnMain`** in `MainAudioGraph`
   (MEDIUM) — classic lock-order deadlock if main ever blocks on
   `graphLock`. Today's earlier mixer livelock fix reduced pressure here,
   but the ordering hazard remains. Fix shape: never dispatch-to-main while
   holding `graphLock`.
8. **`AudioInputCaptureSummaryRing` assumes a single producer** but every
   active input tap (one per audio-input track) writes from the render
   thread (MEDIUM). Fine with one input track; corrupts slots with several.
9. **`AtomicInt32/64` built on deprecated `OSAtomic*`** (LOW-MEDIUM) —
   migrate to Swift `Atomics`/`ManagedAtomic` when touching this code.

## Backlog — duplicate code paths

10. **Destination resolution exists three times**: `Project+Destinations`,
    `LiveSequencerStore+Accessors` (explicitly marked "Phase 2, matches
    Project's equivalents"), and `PlaybackSnapshot`. The store copy was
    transitional and never cleaned up. Consolidate on Project, delegate.
11. **`destinationWriteTarget(for:)` duplicated** in the same two places —
    same consolidation.
12. **Vertical drag-to-value gesture triplicated**: `MacroKnobRow`,
    `StudioRotaryKnob`, `AUMacroSlotKnob` all hand-roll the same
    `StudioDrag.fullRangeTravel` math. Extract one gesture helper.
13. **Phrase-validity state machine repeated 5-6×** in EngineController's
    phrase-navigation paths (`firstValidPhraseID`/`validPhraseID` +
    reset-and-sync boilerplate). Extract a normalize helper.
14. **Pattern-bank default synthesis duplicated** between Project and
    LiveSequencerStore accessors.
15. `lock(); defer { unlock() }` ×10 → `NSLock.withLock` extension (Swift
    ships one; adopt it).
16. `Int(buffer.format.channelCount)` boilerplate ×5 → buffer extension.

## Noted, deliberately not acted on

- `StepOrderPhraseSurfacePresentation`/`StepOrderMapRowPresentation` look
  orphaned after the phrase-panel removal but still back the QA runner's
  status surface and the step-order perform layer's future library home
  (roadmap 26) — keep until that lands.
- `DrumKitPreset` removal is owned by the kits/templates spec (item 27).
- `NoteRepeatInterval` decoding silently defaults on unknown values — same
  forgiving policy as AudioInputChannel now; intentional.
- The "flushTask re-entrancy race" reported by the race audit was a false
  positive (everything is `@MainActor`) — but inspecting it surfaced the
  real cancel-fall-through bug in item 1.
- VisualScenarioCommandRunner statics/notification observers are
  harness-only; consequences are capture-run flakes, already mitigated by
  the pending-command drain + rendered-state waits added today.
