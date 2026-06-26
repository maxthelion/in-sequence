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

Status: Step 3 IMPLEMENTED (uncommitted, machine-verifiable parts). The drum-kit
Sound mini-tab now branches on the member's resolved destination kind
(`Sources/UI/DrumGroup/DrumKitMatrixView+Accordion.swift`):
- `.sample`/`.none`/orphan → existing `SamplerDestinationWidget` (mini sampler +
  in-sampler filter) PLUS a "Load AU…" affordance (`expandedSoundSamplerPanel`).
  "Load AU…" reuses the per-track `AddDestinationSheet`; selecting an AU calls
  `session.setEditedDestination(.auInstrument(componentID:, stateBlob: nil), for: memberID)`
  via `applyMemberSoundDestination`, then `engineController.prepareAudioUnit(for: memberID)`.
- `.auInstrument` → an AU panel (`expandedSoundAUPanel`): instrument-name readout
  (`memberAudioInstrumentChoice`), a Presets button launching `PresetBrowserSheet`
  (reused) bound to the member via `makeMemberPresetBrowserViewModel` —
  `engineController.presetReadout(for: memberID)` / `loadPreset(_, for: memberID)` /
  `session.writeStateBlob(_, target: .track(memberID))` — and an X that clears the
  AU with `session.setEditedDestination(.none, for: memberID)` (the Step-1 clear).
- Pure routing helper `DrumKitSoundTabRouting.usesAUPanel(for:)` decides the branch.

Filter kept dormant-but-stored: the per-track filter is NOT surfaced/applied in the
AU panel; it stays on the part (`track.filter`) and is restored when the part toggles
back to the sampler. `.inheritGroup` is left on the existing sampler/placeholder path
(per-member own-AU only; shared-kit AU is the open product decision in
`docs/human-attention/DECISION-au-group-member-mute.md`).

Machine verification: build SUCCEEDED; both lints (realtime-path, runtime-ownership)
exit 0; new tests in `Tests/SequencerAITests/UI/DrumKitSoundTabAUTests.swift` green
(routing branch, "Load AU…" → setEditedDestination, filter-stays-stored on swap,
member preset browser load→commit), plus existing Step-1 + macro tests still green.

HUMAN RESIDUAL (owner/acoustic tier — NOT verified here): instantiate a REAL AU on a
drum part and confirm it sounds; preset switching changes the sound and persists across
save/reload; the sampler↔AU LIVE swap during playback is click-free / no hung notes
(the AU attach-during-playback leg is the unproven leg per the plan's Rule-5 hazard);
visual layout of the AU panel + "Load AU…" card. Unattended agents cannot instantiate a
real AU or hear audio (AGENTS.md audio tier).
