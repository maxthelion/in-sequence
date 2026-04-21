# Single-Destination Track UI

**Date:** 2026-04-21
**Status:** Design — not yet implemented
**Relates to:** `wiki/pages/track-destinations.md`, `docs/specs/2026-04-20-drum-track-mvp-design.md` (sampler destination), `docs/specs/2026-04-18-north-star-design.md` §Destinations

## Goal

Simplify the Track page's Output panel from a five-card picker to a single-destination slot with explicit Add / Remove affordances. A track either has a destination or it doesn't. When unset, the panel shows one compact row with an "Add Destination" button. When set, it shows a summary row naming the current destination + a Remove button + the destination-type's inline editor. The five always-visible "what-if" choice cards go away; picking a destination is a deliberate modal action.

**Verified by:** Creating a new mono track; observing the Output panel shows "No destination" + "Add Destination"; tapping Add opens a modal with three options (Virtual MIDI Out / AU Instrument / Sampler) and no "Inherit Group" row (the track has no group). Tapping Virtual MIDI Out commits `.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)`, closes the modal, and the Output panel now shows `🎹 MIDI — Virtual MIDI Out · ch 1` with a Remove button and the existing port/channel/offset inline editor below. Tapping Remove returns the panel to the "No destination" state. Repeating on a drum-kit member track: the Add Destination modal shows four options (the three above plus Inherit Group), confirming the group-conditional branch.

## Non-goals

- A separate drum-kit group management page. Drum-kit members keep `.inheritGroup` set at `addDrumKit` time; editing the group's `sharedDestination` from the member's Track page remains scoped to the existing `inheritGroupEditor` placeholder — the full group-editing surface is its own spec.
- Changing the `Destination` enum shape. `.none` keeps its current name and wire format; the UI simply stops offering it as a picker card and treats it as the unset state.
- Data migration. Documents saved with any existing destination decode and render exactly as before.
- Converting `.internalSampler` legacy destinations to `.sample`. `.internalSampler` stays a supported set-state that renders its placeholder tile; it is no longer offered in the Add Destination modal (new sampler destinations use `.sample`).
- Undo / redo beyond SwiftUI's document-based default. Add and Remove mutate `document.project.tracks[i].destination`; the existing undo stack catches it.
- Confirmation dialog on Remove. First-pass behavior is immediate removal; revisit only if user feedback says otherwise.
- Keyboard shortcuts for Add / Remove.

## Principle

A track has at most one destination. The data model already encodes this — `StepSequenceTrack.destination: Destination` is a single-valued property. The existing UI obscures that by rendering all variants as peer choices. Reframing the UI around "set / unset" aligns the surface with the semantics and removes ~five tiles of visual noise on every track page.

The existing `Destination.none` case IS the unset state. This reinterpretation is pure UI — the enum, its Codable form, engine routing, and every downstream assumption remain untouched.

## Architecture

Two surfaces changed, one added.

### 1. Output panel states (`Sources/UI/TrackDestinationEditor.swift`)

Replaces the five-card `.kind`-picker grid with a two-state layout.

**Unset state** (`destination == .none`):

- One `StudioPanel` titled "Output" with eyebrow "Set a destination to route notes".
- A single row: `Text("No destination")` on the left, `Button("Add Destination") { showAddSheet = true }` on the right.
- No inline editor section.

**Set state** (any other case):

- One `StudioPanel` titled "Output" with eyebrow summarising the type ("MIDI", "AU Instrument", "Sampler", "Internal Sampler", "Inherited from group").
- A compact summary row: `[icon] <Type> — <concise detail>` on the left, `Button("Remove") { clearDestination() }` on the right.
- Below the row, the existing destination-type editor renders inline:
  - `.midi` → `midiDestinationEditor` (port picker, channel stepper, note-offset stepper).
  - `.auInstrument` → `auInstrumentEditor` (AU host editor + state-blob management).
  - `.internalSampler` → `internalSamplerEditor` (legacy placeholder tile).
  - `.sample` → `SamplerDestinationWidget` (waveform, prev/next, audition, gain).
  - `.inheritGroup` → `inheritGroupEditor` (informational tile pointing at the group's shared destination).

The summary-row icon + concise-detail formatters live next to the editor as private helpers; they read a `Destination` and return `(Image, String, String)` for icon + type label + detail text.

### 2. Add Destination modal (`Sources/UI/TrackDestination/AddDestinationSheet.swift`, new file)

A SwiftUI sheet presented from the Output panel. Shows three or four tappable rows, each committing a destination on tap and dismissing the sheet.

- **Virtual MIDI Out** — always shown. Sets `.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)`.
- **AU Instrument** — always shown. Opens the existing AU picker inline or as a nested sheet; on picker confirmation, sets `.auInstrument(componentID: picked, stateBlob: nil)`. If the user dismisses the picker without selecting, the Add Destination sheet stays open and no commit happens.
- **Sampler** — always shown. Sets `.sample(sampleID: anyFirstSample, settings: .default)` where `anyFirstSample` is the first sample returned by the library regardless of category (iterate `AudioSampleCategory.allCases` and pick the first `library.firstSample(in:)` that resolves). If the library yields nothing, falls back to `.internalSampler(bankID: .drumKitDefault, preset: "empty")`. The user refines the sample via the inline `SamplerDestinationWidget` after commit — the modal is not responsible for sample choice.
- **Inherit Group** — conditional on `track.groupID != nil`. Sets `.inheritGroup`.

No confirm button; single-tap commits. The sheet has a cancel button (or standard SwiftUI sheet dismissal) that closes without mutation.

The sheet owns no per-option sub-editors — it's a router. Further configuration (which AU, which sample, which MIDI port) happens via the inline editor after commit.

### 3. Default destinations (`Sources/Document/Project+Tracks.swift`)

`Project.defaultDestination(for:)` updates:

```swift
static func defaultDestination(for trackType: TrackType) -> Destination {
    switch trackType {
    case .monoMelodic, .polyMelodic:
        return .none
    case .slice:
        return .internalSampler(bankID: .sliceDefault, preset: "empty-slice")
    }
}
```

`addDrumKit`'s per-member destination assignment is unchanged — members remain `.sample(...)` or `.internalSampler(...)` from the library.

## Data flow

1. The Output panel reads `document.project.tracks[selectedTrackIndex].destination`.
2. Unset state: `Add Destination` sets `@State var showAddSheet = true`, which presents `AddDestinationSheet`.
3. `AddDestinationSheet` is initialised with the current track's `groupID` (to decide whether to show the Inherit Group row) and a closure `onCommit(Destination)`.
4. User taps a row → `onCommit(newDestination)` → sheet closes. The closure writes to `document.project.tracks[selectedTrackIndex].destination`.
5. The `@Binding` on the document triggers a re-render. The Output panel switches to set-state rendering, the inline editor appears, and the engine's `EngineController.apply(documentModel:)` path rewires routing on the next tick (unchanged).
6. Remove: sets `destination = .none` via the same mutation path. Panel re-renders in unset state.

No new observable state, no command-queue changes, no threading implications — the mutation is a straightforward SwiftUI write to an existing property.

## Error handling

- **AU picker dismissed without selection:** Add Destination sheet stays open; no mutation. User can tap another option or cancel.
- **Sampler tapped with an empty library:** commit uses `.internalSampler(bankID: .drumKitDefault, preset: "empty")`. User can edit further via the inline editor. This matches the existing `addDrumKit` fallback behavior.
- **Inherit Group tapped on a track whose group was just removed (race):** commit sets `.inheritGroup`; `inheritGroupEditor` already handles the "group doesn't exist" case with a warning tile. No new handling needed.
- **Removing a destination while the engine is mid-tick:** unchanged from today. `EngineController.apply(documentModel:)` observes the mutation on its next apply cycle; in-flight note-offs flush via the existing `flushDetachedMIDINoteOffs` path.

## Testing

### Unit tests (Document)

- `Tests/SequencerAITests/Document/ProjectAppendTrackDefaultDestinationTests.swift` — new file:
  - `appendTrack(.monoMelodic)` → `selectedTrack.destination == .none`.
  - `appendTrack(.polyMelodic)` → `selectedTrack.destination == .none`.
  - `appendTrack(.slice)` → `selectedTrack.destination == .internalSampler(bankID: .sliceDefault, preset: "empty-slice")` (unchanged; kept as regression assertion).
- `Tests/SequencerAITests/Document/ProjectAddDrumKitDestinationTests.swift` — audit existing test (likely already in `SeqAIDocumentTests.swift` or `ProjectAddDrumKitClipTests.swift`): assert drum-kit members retain their `.sample` / `.internalSampler` destinations. No assertion change expected — this is a regression guard.

### UI tests (smoke, manual)

No automated UI test harness today. Manual verification:

1. Open a new project → Tracks workspace shows default mono track.
2. Open Track page → Output panel shows "No destination" + Add Destination button.
3. Tap Add Destination → modal opens with three rows (Virtual MIDI Out, AU Instrument, Sampler). "Inherit Group" absent.
4. Tap Virtual MIDI Out → modal closes. Output panel shows `🎹 MIDI — Virtual MIDI Out · ch 1` + Remove. Port / channel / offset editor visible below.
5. Tap Remove → panel returns to "No destination" state.
6. Add an 808 drum kit → member tracks (Kick, Snare, Hat, Clap) all show their sampler destination already set (summary row + waveform widget).
7. Select one drum-kit member → tap Remove → destination becomes `.none`. Tap Add Destination → modal now shows FOUR rows including Inherit Group. Tap Inherit Group → destination becomes `.inheritGroup`; the inherit-group placeholder tile renders.

### Visual regression guard

Screenshot the Output panel in both states on the main project before merge; retake after merge; diff. Any visual delta beyond the layout change is unintended and should be investigated.

## Scope

Single plan, ~5 files. Focused on `TrackDestinationEditor.swift` rewrite + one new sheet file + a one-line default change in `Project+Tracks.swift`. No spec decomposition needed.

## Decisions taken

- `.none` is the unset state. No new enum case, no `Destination?` optional.
- Inherit Group is hidden from the modal when the track has no `groupID`. Shown otherwise.
- New mono/poly tracks default to `.none`; new slice tracks keep `.internalSampler(.sliceDefault)` because slice playback without a sampler is meaningless; drum-kit member destinations are unchanged.
- Set state renders a compact summary row plus the existing type-specific inline editor. No behind-a-modal editing round-trip.
- Remove is immediate, no confirmation. Revisit only if feedback demands.
- `.internalSampler` legacy destinations continue to work in the set state; they are no longer offered in the Add Destination modal (Sampler there means `.sample`).
- AU Instrument modal-row opens the existing AU picker on tap; commit happens after AU selection. No dry `.auInstrument` with an empty componentID is ever written.
- Sampler modal-row commits `.sample(sampleID: anyFirstSample, settings: .default)` using the first sample the library yields across any category; user picks further samples via the inline SamplerDestinationWidget afterward. Library-empty fallback is `.internalSampler(bankID: .drumKitDefault, preset: "empty")`.
