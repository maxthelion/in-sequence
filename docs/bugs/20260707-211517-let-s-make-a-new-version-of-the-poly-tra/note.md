Let's make a new version of the poly track which is called a chord track. The idea is to make it more like the slicer track, where the list of chosen chords go above the tabbed interface, and there is a tab for "chords", where they are chosen and edited. the step sequencer could then have chords from the set placed on it, like slices get put on the slicer step sequencer. There is a slight issue in both views that the parameters for the individual slice/chord are a bit awkward. We can perhaps resolve this for chords by making inversion etc layers that can be changed per step.

Screenshots:
- 22g-track-generator-chord-instrument.png

Capture references:
- 22g-track-generator-chord-instrument.png (in-sequence/qa-generator-bugfixes; main @ edf0ce13; run 20260707-125042-in-sequence-qa-generator-bugfixes-main-edf0ce13; 6824750313c45762332225b71e463577)

2026-07-07 triage: left OPEN intentionally. This is a dedicated chord-track
MVP, not a cosmetic rename of the poly generator surface. Split plan:
`docs/plans/2026-07-07-chord-track-mvp-architecture.md`.

Status: RESOLVED 2026-07-08

Implemented as a real `TrackType.chord` with track-owned `ChordPalette`, chord-reference clip content, palette-slot playback resolution, inversion, bake-to-note-grid while retaining the source recipe clip, creation-flow entry, chord workspace tabs, and visual-command coverage.

Verification:
- Build: `xcodebuild build -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS'`
- Focused tests: `ChordsTests`, `StepGridCoordinatorTests`, `StepGridEditParityTests`, `ClipContentSliceTriggerModeTests`, `ProjectAppendTrackClipTests` (70 tests, 0 failures)
- Lints: `scripts/diagnostics/ux-canon-lint.sh`, `scripts/diagnostics/realtime-path-lint.sh`, `scripts/diagnostics/runtime-ownership-lint.sh`, `git diff --check`
- Visual evidence: http://localhost:4747/gallery?run=20260708-083510-in-sequence-qa-surface-coverage-main-923a889d
- Rows: `23h-track-chord-steps`, `23i-track-chord-chords-tab`, `23j-track-chord-inversion-layer`

Note: the full QA capture later aborted during drum-kit rows with the pre-existing `playerTime.sampleTimeValid` AVFAudio signature; that is recorded separately in `docs/bugs/20260708-093533-qa-capture-avfaudio-player-time-sampletimevalid/`.
