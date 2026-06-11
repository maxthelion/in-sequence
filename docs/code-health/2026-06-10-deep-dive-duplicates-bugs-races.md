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

## Engine threading — done 2026-06-11

5. **`transportTickIndex` torn/stale reads** — FIXED. The tick is now
   backed by `transportTickAtomic`, written synchronously on the tick queue
   at prepare time; all engine-internal readers (`armAudioInput`
   quantization, note-repeat engage anchor, playback-position estimation)
   read `currentTransportTick`. The `@Observable` property remains a
   main-published mirror for UI only.
6. **Note-repeat dictionaries** — audited: all accesses are consistently
   under `withStateLock` (the "escapes" were copy-outs by value — fine).
   The real finding was `reconcileNoteRepeats` holding `stateLock` across
   `supportsNoteRepeat`, which acquires `phraseNavigationLock` — a pinned
   lock ordering. FIXED: keys are copied out first; evaluation runs outside
   the lock.
7. **`graphLock` held across `performOnMain`** — FIXED. All 22 sites
   inverted: the lock is now acquired *inside* the main-thread closure, so
   no thread ever holds `graphLock` while entering
   `DispatchQueue.main.sync`. Mutual exclusion is unchanged (every locker
   takes the same lock); the deadlock shape is structurally gone.
8. **`AudioInputCaptureSummaryRing`** — audited: writers are actually
   multi-producer safe (atomic sequence claim → distinct slot per writer).
   The real gap was a torn read in `drain` when a writer laps the slot
   mid-copy. FIXED with a seqlock-style re-check after copying.

## Backlog — engine threading, remaining

9. **`AtomicInt32/64` built on deprecated `OSAtomic*`** (LOW-MEDIUM) —
   migration needs a decision: `Synchronization.Atomic` requires macOS 15
   (target is 14.0), so it means adding the swift-atomics package. Owner
   call; the OSAtomic implementations are correct meanwhile.

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

## Addendum 2026-06-11: observable-mutation-under-lock is a class

Two runtime-confirmed instances now: the mixer page exportToProject
livelock (2026-06-10) and the audio-input revision-bump deadlock
(2026-06-11, hit the moment live input levels published). The pattern:
mutating any @Observable property while holding stateLock (or from
inside a SwiftUI render path) lets Observation synchronously re-enter
view bodies that read engine state through the same lock. Standing
audit item: no `@Observable` property write inside `withStateLock` —
sweep EngineController for the remaining observable properties
(isRunning, currentBPM, transportPosition, currentPhraseID,
chordContextByLane, …) and verify each write site is outside the lock.
