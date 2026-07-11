Pattern copy/paste, occupancy, and Randomize can address the wrong slot

Observed:
- Copying one pattern and navigating to another before Paste could keep the
  old right-click operation selection as the destination.
- Pattern occupancy marked any referenced clip as data, including a newly
  initialized empty clip.
- Randomize used the phrase-selected playback slot rather than the pattern
  currently displayed in the track editor.

## ROOT CAUSE + FIX

Viewed, playback-selected, and operation-selected pattern identities were
allowed to drift without an explicit edit-target rule.

- Left-click pattern navigation now clears stale operation selection, making
  the newly viewed slot the destination for Paste and other edit commands.
- Randomize passes the viewed `PatternSlotAddress` directly.
- Occupancy is shared across track, slicer, audio-input, and drum-kit views and
  requires playable clip data, authored clip automation/randomize state, or a
  valid generator.

Acceptance:
- Clipboard paste clones the source into the newly viewed destination slot.
- Randomizing viewed P2 cannot mutate phrase-selected P1.
- A populated P1 plus initialized-empty P2-P5 reports one occupied slot.
- QA row: `18a-track-pattern-occupancy`.

Verification: 65 focused clipboard, randomize, harness, occupancy, and drum-kit
tests passed; UX canon lint passed with zero violations.

Status: RESOLVED
