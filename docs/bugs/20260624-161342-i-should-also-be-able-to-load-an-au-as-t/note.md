I should also be able to load an AU as the sound for a drum part. It would replace the sampler + filter combo when loaded. We might need a capture of the empty part if the cross is clicked.

Screenshots:
- 29g-drum-kit-expanded-row.png

Status: RESOLVED (Step 1 — X-click clear, uncommitted) The drum-kit Sound mini-tab's
X (remove) button now clears the member part's sound. `expandedSoundTab`'s `onRemove`
(`Sources/UI/DrumGroup/DrumKitMatrixView+Accordion.swift`) was a no-op `{}`; it now
calls `session.setEditedDestination(.none, for: memberID)`, mirroring the per-track
precedent `TrackDestinationEditor.clearDestination`. The clear flows through the normal
undoable document edit path (`batch(.fullEngineApply)` → `writeBackProjectStructure`),
which ramp-removes the live sample voice via `syncSampleMixers` (Hard-Rule-5 safe). It
does NOT write a transient "empty" capture into the `.seqai` document
(`DrumKitMatrixView+Capture.swift` only saves note-clip windows to pattern slots and
was correctly left untouched). After clearing, the part stays a kit member and the
Sound tab renders the existing `SamplerDestinationWidget` orphan/placeholder card (no
crash, no hang). Covered by `test_setEditedDestination_none_clearsKitMemberSound` in
`Tests/SequencerAITests/App/SessionDestinationMacroTests.swift`.

Step 3 (AU-load UI: surfacing an AU + preset picker in the Sound tab to replace the
sampler+filter) remains OPEN — not implemented here.
