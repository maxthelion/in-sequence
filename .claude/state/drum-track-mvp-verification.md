# Drum Track MVP — Verification Record

**Date:** 2026-04-20
**Branch:** `feat/drum-track-mvp` (worktree at `.worktrees/drum-track-mvp`)
**Plan:** `docs/plans/2026-04-20-drum-track-mvp.md`
**Commit range:** `126c7db..HEAD` (19 commits total: 17 implementation + 1 gitignore fix + 1 plan/spec)

## Automated checks

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme SequencerAI test` → **`** TEST SUCCEEDED **`**. 278 tests, 3 pre-existing skips, 0 failures. One pre-existing flaky test (`TickClockTests.test_tick_index_starts_at_zero_and_increments_without_gaps`) passed this run.

- `grep -rn suggestedSharedDestination Sources/ Tests/` → zero code matches. Remaining historical references are only in `docs/specs/` and `docs/plans/`.

- `grep -rn '\.sample(sampleID:' Sources/` → confined to 3 files as expected:
  - `Sources/Document/Project+Tracks.swift` (addDrumKit assignment)
  - `Sources/UI/TrackDestinationEditor.swift` (applyDestinationChoice seed)
  - `Sources/UI/SamplerDestinationWidget.swift` (all widget bindings)

- `grep -rn AudioSampleLibrary Sources/` → 6 files: App init, library definition, engine controller, destination editor, widget, Project+Tracks. Correct surface.

## Manual smokes (deferred — require a GUI launch not feasible in this automation env)

The implementer and reviewer were automation agents; launching SequencerAI.app interactively is not part of this loop. The following smokes must be executed manually before the feature is user-facing:

1. Launch the app → new project → **Add Drum Kit (808)** → press play. Hear kick on steps 1/5/9/13, snare on 5/13, hat on every other step, clap on 13.
2. Select the kick track → destination editor renders `SamplerDestinationWidget` → press **Audition** without transport → hear the kick once.
3. Press `[←]` / `[→]` in the widget → sample name changes to the next kick → audition → hear the new kick.
4. Drag gain slider to -30 dB → audition → quieter. Release near 0 → snaps to 0.0 dB.
5. Set mute layer cell to `.single(.bool(true))` on kick → play → kick silent; other drums keep playing.
6. Delete `~/Library/Application\ Support/sequencer-ai/samples/` → relaunch → directory re-populates from the bundle.
7. Switch a melodic track's destination to Sampler manually → default kick loads → prev/next walks the library.

## Noted during implementation

- **Bug fixed in `addDrumKit` (Task 14):** the prior implementation did not append `TrackPatternBank` entries for the new drum tracks — silent bug since `syncPhrasesWithTracks()` partially compensated. Now handled correctly.
- **Mute-filter gap closed (Task 11 review):** the sample dispatch loop initially checked only the phrase-layer mute (`currentLayerSnapshot.isMuted(trackID)`); mix-mute (`track.mix.isMuted`) was bypassed. Fix added both guards to match the AU loop; new test `test_mixMute_suppressesSampleDispatch` locks in behaviour.
- **`EngineController.swift` size:** 1249 lines, already over the 1000-line soft limit before Task 11's +34 lines. Not a regression caused by this plan, but worth flagging for the next task that touches the file — a split into `EngineController+SampleDispatch.swift` or similar would bring it back under 1000.
- **Starter samples are silent placeholders.** The 9 bundled WAVs are 0.1s mono silence. Full audible verification requires procuring CC0 drum samples and swapping them in — filename stability preserves the `UUIDv5` IDs so no document-side migration is needed.
