# Single-Destination Track UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Output panel's 5-card always-visible destination picker with a single-destination surface: unset state shows an "Add Destination" button, set state shows a compact summary row + Remove + the existing type-specific inline editor. New mono/poly tracks default to unset; slice tracks and drum-kit members are unchanged.

**Architecture:** UI-only for the primary change. `Destination.none` is reinterpreted as the unset state — no enum change. `Sources/UI/TrackDestinationEditor.swift` is rewritten to switch between unset and set rendering. A new `Sources/UI/TrackDestination/AddDestinationSheet.swift` owns the modal's 3-or-4 option list. One document-side change: `Project.defaultDestination(for:)` returns `.none` for mono/poly.

**Tech Stack:** Swift 5.9+, SwiftUI (`.sheet`), XCTest. No new dependencies.

**Parent spec:** `docs/specs/2026-04-21-single-destination-ui-design.md`.

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. After creating files under `Sources/UI/TrackDestination/`, run `xcodegen generate`.

**Status:** Not started. Tag `v0.0.20-single-destination-ui` at completion.

**Depends on:** nothing on the critical path. Can execute against current `main`.

**Deliberately deferred:**

- Drum-kit group management page (its own future spec).
- Removing `.internalSampler` from the enum. Backward-compat retained; it's a valid set-state, just not offered in the Add modal.
- Any data migration. `.none` semantics don't change at the wire level.
- Keyboard shortcuts. Not in scope.

---

## File Structure

```
Sources/Document/
  Project+Tracks.swift                       # MODIFIED — defaultDestination(for:) returns .none for mono/poly

Sources/UI/
  TrackDestinationEditor.swift               # REWRITTEN body — unset state + set state split; keeps existing editor subviews
  TrackDestination/
    AddDestinationSheet.swift                # NEW — modal presenting 3 or 4 destination options
    DestinationSummary.swift                 # NEW — pure value helper: (Destination, Project) → (iconName, typeLabel, detail)

Tests/SequencerAITests/
  Document/
    ProjectAppendTrackDefaultDestinationTests.swift   # NEW — verifies new defaults
  UI/
    DestinationSummaryTests.swift            # NEW — label/detail formatting
```

---

## Task 1: `Project.defaultDestination(for:)` returns `.none` for mono/poly

**Files:**
- Modify: `Sources/Document/Project+Tracks.swift:148-155`
- Test: `Tests/SequencerAITests/Document/ProjectAppendTrackDefaultDestinationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/Document/ProjectAppendTrackDefaultDestinationTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAppendTrackDefaultDestinationTests: XCTestCase {
    func test_appendTrack_monoMelodic_defaults_to_none() {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        XCTAssertEqual(project.selectedTrack.destination, .none)
    }

    func test_appendTrack_polyMelodic_defaults_to_none() {
        var project = Project.empty
        project.appendTrack(trackType: .polyMelodic)
        XCTAssertEqual(project.selectedTrack.destination, .none)
    }

    func test_appendTrack_slice_defaults_to_internalSampler() {
        var project = Project.empty
        project.appendTrack(trackType: .slice)
        guard case .internalSampler(let bankID, let preset) = project.selectedTrack.destination else {
            return XCTFail("expected .internalSampler default for slice track; got \(project.selectedTrack.destination)")
        }
        XCTAssertEqual(bankID, .sliceDefault)
        XCTAssertEqual(preset, "empty-slice")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectAppendTrackDefaultDestinationTests \
  2>&1 | tail -30
```

Expected: `test_appendTrack_monoMelodic_defaults_to_none` and `test_appendTrack_polyMelodic_defaults_to_none` both fail — they currently default to `.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)`. The slice test passes.

- [ ] **Step 3: Update `defaultDestination(for:)`**

In `Sources/Document/Project+Tracks.swift`, replace the `defaultDestination(for:)` method:

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

- [ ] **Step 4: Run the test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectAppendTrackDefaultDestinationTests \
  2>&1 | tail -15
```

Expected: all three tests pass.

- [ ] **Step 5: Run the full test suite to check for regressions**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -15
```

Expected: all tests pass. Other test files may have previously asserted `track.destination.midiPort == .sequencerAIOut` on the result of `appendTrack`; those assertions need updating. If any test fails, change its expectation to `.none` for mono/poly — the change is intentional per the spec.

- [ ] **Step 6: Commit**

```bash
git add Sources/Document/Project+Tracks.swift Tests/SequencerAITests/Document/ProjectAppendTrackDefaultDestinationTests.swift
git commit -m "feat(document): mono/poly tracks default to unset destination (.none)"
```

---

## Task 2: `DestinationSummary` — pure value helper

A small value-level helper that takes a `Destination` plus the `Project` context and returns `(iconName: String, typeLabel: String, detail: String)`. Used by the set-state summary row. Pure function, easy to unit-test, keeps icon / label / detail formatting out of the view body.

**Files:**
- Create: `Sources/UI/TrackDestination/DestinationSummary.swift`
- Test: `Tests/SequencerAITests/UI/DestinationSummaryTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/UI/DestinationSummaryTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class DestinationSummaryTests: XCTestCase {
    func test_midi_summary() {
        let dest = Destination.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        let summary = DestinationSummary.make(for: dest, in: .empty, trackID: Project.empty.selectedTrackID)
        XCTAssertEqual(summary.typeLabel, "MIDI")
        XCTAssertEqual(summary.iconName, "pianokeys")
        XCTAssertTrue(summary.detail.contains("SequencerAI Out"))
        XCTAssertTrue(summary.detail.contains("ch 1"))
    }

    func test_midi_transpose_appears_when_nonzero() {
        let dest = Destination.midi(port: .sequencerAIOut, channel: 3, noteOffset: 7)
        let summary = DestinationSummary.make(for: dest, in: .empty, trackID: Project.empty.selectedTrackID)
        XCTAssertTrue(summary.detail.contains("ch 4"))
        XCTAssertTrue(summary.detail.contains("+7"))
    }

    func test_auInstrument_summary() {
        let dest = Destination.auInstrument(
            componentID: AudioComponentID(type: "aumu", subtype: "dex1", manufacturer: "DSPP", version: 0),
            stateBlob: nil
        )
        let summary = DestinationSummary.make(for: dest, in: .empty, trackID: Project.empty.selectedTrackID)
        XCTAssertEqual(summary.typeLabel, "AU Instrument")
        XCTAssertEqual(summary.iconName, "waveform")
    }

    func test_sample_summary_with_missing_sample() {
        let dest = Destination.sample(sampleID: UUID(), settings: .default)
        let summary = DestinationSummary.make(for: dest, in: .empty, trackID: Project.empty.selectedTrackID)
        XCTAssertEqual(summary.typeLabel, "Sampler")
        XCTAssertEqual(summary.iconName, "speaker.wave.2")
        XCTAssertEqual(summary.detail, "Sample not in library")
    }

    func test_internalSampler_summary() {
        let dest = Destination.internalSampler(bankID: .sliceDefault, preset: "empty-slice")
        let summary = DestinationSummary.make(for: dest, in: .empty, trackID: Project.empty.selectedTrackID)
        XCTAssertEqual(summary.typeLabel, "Internal Sampler")
        XCTAssertEqual(summary.iconName, "rectangle.stack")
    }

    func test_inheritGroup_with_no_group_shows_detached() {
        let dest = Destination.inheritGroup
        let summary = DestinationSummary.make(for: dest, in: .empty, trackID: Project.empty.selectedTrackID)
        XCTAssertEqual(summary.typeLabel, "Inherit Group")
        XCTAssertEqual(summary.detail, "Not in a group")
    }

    func test_none_summary_is_empty_marker() {
        let summary = DestinationSummary.make(for: .none, in: .empty, trackID: Project.empty.selectedTrackID)
        XCTAssertEqual(summary.typeLabel, "")
        XCTAssertEqual(summary.iconName, "")
        XCTAssertEqual(summary.detail, "")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/DestinationSummaryTests \
  2>&1 | tail -30
```

Expected: compile failure — `DestinationSummary` does not exist.

- [ ] **Step 3: Create the helper**

Write `Sources/UI/TrackDestination/DestinationSummary.swift`:

```swift
import Foundation

struct DestinationSummary: Equatable {
    let iconName: String
    let typeLabel: String
    let detail: String

    static func make(for destination: Destination, in project: Project, trackID: UUID) -> DestinationSummary {
        switch destination {
        case let .midi(port, channel, noteOffset):
            let portName = port?.displayName ?? "Unassigned"
            var parts: [String] = [portName, "ch \(Int(channel) + 1)"]
            if noteOffset != 0 {
                parts.append("\(noteOffset > 0 ? "+" : "")\(noteOffset) st")
            }
            return DestinationSummary(
                iconName: "pianokeys",
                typeLabel: "MIDI",
                detail: parts.joined(separator: " · ")
            )
        case .auInstrument:
            return DestinationSummary(
                iconName: "waveform",
                typeLabel: "AU Instrument",
                detail: "Audio Unit hosted in-app"
            )
        case let .sample(sampleID, _):
            let sampleName = AudioSampleLibrary.shared.sample(id: sampleID)?.displayName ?? "Sample not in library"
            return DestinationSummary(
                iconName: "speaker.wave.2",
                typeLabel: "Sampler",
                detail: sampleName
            )
        case let .internalSampler(bankID, _):
            return DestinationSummary(
                iconName: "rectangle.stack",
                typeLabel: "Internal Sampler",
                detail: bankID.rawValue
            )
        case .inheritGroup:
            let group = project.group(for: trackID)
            let detail: String = {
                guard let group else { return "Not in a group" }
                return group.name
            }()
            return DestinationSummary(
                iconName: "arrow.turn.up.right",
                typeLabel: "Inherit Group",
                detail: detail
            )
        case .none:
            return DestinationSummary(iconName: "", typeLabel: "", detail: "")
        }
    }
}
```

If `AudioSampleLibrary.shared.sample(id:)` or `AudioSample.displayName` do not exist on the library type, check `Sources/Audio/AudioSampleLibrary.swift` for the actual accessor name. Common variants: `sample(by:)`, `sampleByID(_:)`, or a subscript. Use whichever matches the repo's actual API; update the test's expected string to match. If the API truly can't return a name, fall back to `sampleID.uuidString.prefix(8) + "…"`.

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/DestinationSummaryTests \
  2>&1 | tail -15
```

Expected: all seven tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/UI/TrackDestination/DestinationSummary.swift Tests/SequencerAITests/UI/DestinationSummaryTests.swift project.yml
git commit -m "feat(ui): DestinationSummary helper for set-state summary row"
```

---

## Task 3: `AddDestinationSheet` — the modal

A SwiftUI sheet presenting 3 or 4 tappable rows. Each row commits a destination via an `onCommit(Destination)` closure and dismisses. Cancel dismisses without mutation.

**Files:**
- Create: `Sources/UI/TrackDestination/AddDestinationSheet.swift`

The `AddDestinationSheet` is a pure presentation component — it takes the track's context (whether it's in a group) and returns a selected destination via its callback. It does not read from or write to the document directly; the caller handles mutation and engine apply.

- [ ] **Step 1: Create the sheet**

Write `Sources/UI/TrackDestination/AddDestinationSheet.swift`:

```swift
import SwiftUI

struct AddDestinationSheet: View {
    let isInGroup: Bool
    let auInstruments: [AudioInstrumentChoice]
    let onCommit: (Destination) -> Void
    let onCancel: () -> Void

    @State private var stage: Stage = .root

    private enum Stage {
        case root
        case pickingAUInstrument
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            switch stage {
            case .root:
                rootOptions
            case .pickingAUInstrument:
                auInstrumentPicker
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 320)
        .background(StudioTheme.chrome)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stage == .root ? "Add Destination" : "Pick AU Instrument")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)
            Text(stage == .root ? "Choose how this track should output notes." : "Commit happens when you pick a voice.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
        }
    }

    private var rootOptions: some View {
        VStack(spacing: 10) {
            if isInGroup {
                optionRow(
                    icon: "arrow.turn.up.right",
                    title: "Inherit Group",
                    detail: "Follow the shared destination owned by this track's group."
                ) {
                    onCommit(.inheritGroup)
                }
            }

            optionRow(
                icon: "pianokeys",
                title: "Virtual MIDI Out",
                detail: "Send note data to a MIDI endpoint."
            ) {
                onCommit(.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0))
            }

            optionRow(
                icon: "waveform",
                title: "AU Instrument",
                detail: "Host an Audio Unit instrument in-app."
            ) {
                stage = .pickingAUInstrument
            }

            if AudioSampleLibrary.shared.samples.isEmpty {
                optionRow(
                    icon: "speaker.wave.2",
                    title: "Sampler",
                    detail: "Library empty — commits to internal sampler placeholder."
                ) {
                    onCommit(.internalSampler(bankID: .drumKitDefault, preset: "empty"))
                }
            } else {
                optionRow(
                    icon: "speaker.wave.2",
                    title: "Sampler",
                    detail: "Play one-shot sample files."
                ) {
                    let seed = AudioSampleCategory.allCases
                        .lazy
                        .compactMap { AudioSampleLibrary.shared.firstSample(in: $0) }
                        .first
                    if let seed {
                        onCommit(.sample(sampleID: seed.id, settings: .default))
                    } else {
                        onCommit(.internalSampler(bankID: .drumKitDefault, preset: "empty"))
                    }
                }
            }
        }
    }

    private var auInstrumentPicker: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(auInstruments, id: \.audioComponentID.displayKey) { choice in
                    optionRow(
                        icon: "waveform",
                        title: choice.displayName,
                        detail: choice.audioComponentID.displayKey
                    ) {
                        onCommit(.auInstrument(componentID: choice.audioComponentID, stateBlob: nil))
                    }
                }
            }
        }
    }

    private func optionRow(
        icon: String,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(StudioTheme.cyan)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .padding(14)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
```

If `AudioInstrumentChoice.displayName` doesn't exist, use `choice.audioComponentID.displayKey` or inspect `Sources/UI/VoicePickerView.swift` for the actual display-name accessor. Keep this as a one-line fix when building.

- [ ] **Step 2: Build**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: build succeeds. If it fails due to API name mismatches (the `AudioInstrumentChoice.displayName` or similar), fix inline and retry.

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/TrackDestination/AddDestinationSheet.swift project.yml
git commit -m "feat(ui): AddDestinationSheet with 3-or-4 option modal (Inherit Group conditional)"
```

---

## Task 4: Rewrite `TrackDestinationEditor.body` to unset / set layout

Replace the destination selector (5-card grid) with the set/unset split. Keep the existing editor subviews (`midiEditor`, `auEditor`, `samplerEditor`, `internalSamplerEditor`, `inheritGroupEditor`) unchanged — they render inline after the summary row in the set state. Replace `applyDestinationChoice(_:)` with a smaller `commit(destination:)` method used by both the modal callback and the Remove button.

**Files:**
- Modify: `Sources/UI/TrackDestinationEditor.swift`

- [ ] **Step 1: Delete the now-unused `availableChoices`, `supportsInternalSamplerChoice`, `applyDestinationChoice`, `destinationSelector`, `DestinationChoiceCard`, and `TrackDestinationChoice`**

These members become dead after Step 2 replaces the body. Delete them explicitly so nothing lingers. Also delete the `noneEditor` computed property — the unset state renders a different view.

After deletion, the file should contain:
- The `TrackDestinationEditor` struct with only: `track`, `editedDestination`, `currentWriteTarget`, `currentAudioInstrumentChoice`, the audio-binding helpers, MIDI binding helpers, recent-voices plumbing, `prepareAndOpenCurrentAudioUnitWindow` / `openCurrentAudioUnitWindow`, `saveCurrentVoiceSnapshot`, `recordVoiceSnapshot`, `recallRecentVoice`, `refreshRecentVoices`, and the subviews: `midiEditor`, `auEditor`, `samplerEditor`, `internalSamplerEditor`, `inheritGroupEditor`.
- The private `DestinationField` struct (still used by `midiEditor`).
- No `TrackDestinationChoice` enum, no `DestinationChoiceCard` struct, no `availableChoices`, no `destinationSelector`, no `applyDestinationChoice`, no `noneEditor`, no `supportsInternalSamplerChoice`.

Use Edit with precise `old_string` selectors to delete each named member one at a time. Do not consolidate deletions — do them step by step so the diff stays traceable.

- [ ] **Step 2: Replace `body` with the unset / set split**

Replace the `var body: some View` block (currently lines 51–77 of the original file, though line numbers will have shifted after Step 1) with:

```swift
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioPanel(title: "Output", eyebrow: panelEyebrow, accent: panelAccent) {
                VStack(alignment: .leading, spacing: 12) {
                    if isUnset {
                        unsetRow
                    } else {
                        setSummaryRow
                    }
                }
            }

            if !isUnset {
                inlineEditor
            }
        }
        .task(id: track.id) {
            refreshRecentVoices()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddDestinationSheet(
                isInGroup: track.groupID != nil,
                auInstruments: engineController.availableAudioInstruments,
                onCommit: { destination in
                    showingAddSheet = false
                    commit(destination: destination)
                },
                onCancel: {
                    showingAddSheet = false
                }
            )
        }
    }

    private var isUnset: Bool {
        if case .none = editedDestination { return true }
        return false
    }

    private var panelEyebrow: String {
        isUnset ? "Set a destination to route notes" : DestinationSummary.make(for: editedDestination, in: document.project, trackID: track.id).typeLabel
    }

    private var panelAccent: Color {
        switch editedDestination {
        case .midi: return StudioTheme.cyan
        case .auInstrument: return StudioTheme.success
        case .sample: return StudioTheme.violet
        case .internalSampler: return StudioTheme.amber
        case .inheritGroup: return StudioTheme.success
        case .none: return StudioTheme.mutedText
        }
    }

    private var unsetRow: some View {
        HStack(spacing: 12) {
            Text("No destination")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
            Spacer(minLength: 0)
            Button("Add Destination") { showingAddSheet = true }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.success)
        }
    }

    private var setSummaryRow: some View {
        let summary = DestinationSummary.make(for: editedDestination, in: document.project, trackID: track.id)
        return HStack(spacing: 12) {
            Image(systemName: summary.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(panelAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.typeLabel)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
                Text(summary.detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Remove") { commit(destination: .none) }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var inlineEditor: some View {
        switch editedDestination {
        case .midi:
            midiEditor
        case .auInstrument:
            auEditor
        case .sample:
            samplerEditor
        case .internalSampler:
            internalSamplerEditor
        case .inheritGroup:
            inheritGroupEditor
        case .none:
            EmptyView()
        }
    }

    private func commit(destination: Destination) {
        if case .auInstrument = editedDestination, !isAUEquivalent(destination) {
            AUWindowHost.shared.close(for: currentAUWindowKey)
        }
        document.project.setEditedDestination(destination, for: track.id)
        engineController.apply(documentModel: document.project)
        if case .auInstrument = destination {
            engineController.prepareAudioUnit(for: track.id)
            saveCurrentVoiceSnapshot()
        }
    }

    private func isAUEquivalent(_ destination: Destination) -> Bool {
        if case .auInstrument = destination { return true }
        return false
    }
```

- [ ] **Step 3: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: build succeeds. Common failure points:
- `StudioPanel(title:, eyebrow:, accent:) { … }` signature — if it differs (e.g., requires `content:`), adjust the call.
- `engineController.availableAudioInstruments` type — check `Sources/Engine/EngineController.swift` for the concrete type returned and adjust `AddDestinationSheet`'s `auInstruments: [AudioInstrumentChoice]` param type to match.
- The `.task(id:)` modifier has to sit on a concrete-typed view — should work, but if a `Type 'some View' has no member 'task'` error occurs, wrap with `.onAppear`.

Fix any mismatches inline, then rebuild.

- [ ] **Step 4: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all tests pass. The test updated in Task 1 and the new tests added in Tasks 1–2 are already covered.

- [ ] **Step 5: Commit**

```bash
git add Sources/UI/TrackDestinationEditor.swift
git commit -m "feat(ui): TrackDestinationEditor uses unset/set layout with Add Destination sheet"
```

---

## Task 5: Manual smoke test + tag

**Files:** none (verification + tag + status)

- [ ] **Step 1: Build and open the app**

```bash
./scripts/open-latest-build.sh
```

- [ ] **Step 2: Verify the new-project flow**

- Open a fresh project; select the default mono-melodic track.
- Navigate to the Track page (top bar → "TRACK").
- Expect the Output panel to show `"No destination"` + `"Add Destination"` button.
- Tap Add Destination. Expect the modal to open with THREE rows (Virtual MIDI Out, AU Instrument, Sampler). No "Inherit Group" row.
- Tap Virtual MIDI Out. Expect the modal to close. The Output panel now shows a summary row (`pianokeys` icon, "MIDI", "SequencerAI Out · ch 1") with a Remove button and the port/channel/offset inline editor below.
- Tap Remove. Expect the panel to flip back to the "No destination" state.

- [ ] **Step 3: Verify the drum-kit member flow**

- Add Drum Kit → 808. Select the Kick track.
- Expect the Output panel to show the `Sampler` summary row (with the kick sample name from the library) and the `SamplerDestinationWidget` inline.
- Tap Remove. Expect unset state.
- Tap Add Destination. Expect FOUR rows this time (Inherit Group + the three above). Confirm "Inherit Group" is the top row.
- Tap Inherit Group. Expect the panel to show "Inherit Group" summary row + the `inheritGroupEditor` tile.

- [ ] **Step 4: Verify AU selection**

- Select a non-grouped mono track (if needed, add one and remove its destination).
- Tap Add Destination → AU Instrument. Expect the sheet to transition to the AU instrument picker list.
- Tap any instrument. Expect the sheet to close and the Output panel to show the AU inline editor with that instrument selected.
- Tap Remove. Expect unset.

- [ ] **Step 5: Verify empty-library Sampler fallback**

If the starter sample library is populated (the usual case), skip this step. If testing with an emptied library: Tap Sampler → expect commit to `.internalSampler(bankID: .drumKitDefault, preset: "empty")`; the panel shows the internalSamplerEditor placeholder tile.

- [ ] **Step 6: Flip plan status + tag**

Edit `docs/plans/2026-04-21-single-destination-ui.md`: replace `**Status:** Not started.` with `**Status:** ✅ Completed 2026-04-21. Tag v0.0.20-single-destination-ui.`

```bash
git add docs/plans/2026-04-21-single-destination-ui.md
git commit -m "docs(plan): mark single-destination-ui completed"
git tag -a v0.0.20-single-destination-ui -m "Single-destination Track UI: unset/set layout + Add Destination modal"
```

- [ ] **Step 7: Dispatch `wiki-maintainer` to refresh `wiki/pages/track-destinations.md`**

Brief:
- Diff range: `<previous-tag>..HEAD`.
- Plan: `docs/plans/2026-04-21-single-destination-ui.md`.
- Task: update `wiki/pages/track-destinations.md` to describe the new unset/set surface. Note that `.none` is the unset state, that the Add modal hides Inherit Group for non-grouped tracks, and that new mono/poly tracks default unset.
- Commit under `docs(wiki):` prefix.

---

## Self-Review

**Spec coverage:**
- `.none` IS the unset state — Task 4 Step 2 `isUnset` check. ✓
- Add Destination modal with 3 or 4 rows (Inherit Group conditional) — Task 3 `isInGroup` branch. ✓
- Hybrid defaults (mono/poly → `.none`, slice unchanged) — Task 1 Step 3. ✓
- Set state = summary row + Remove + inline editor — Task 4 Step 2 `setSummaryRow` + `inlineEditor`. ✓
- Remove immediate, no confirmation — Task 4 Step 2 `commit(destination: .none)`. ✓
- `.internalSampler` remains a valid set-state but not offered in modal — Task 3 root options omits it; `inlineEditor` branch renders it if the destination is already `.internalSampler`. ✓
- AU picker nested inside the sheet — Task 3 `.stage = .pickingAUInstrument`. ✓
- Sampler commits with library's first-any-category sample, falls back to `.internalSampler(.drumKitDefault, "empty")` — Task 3 `rootOptions` sampler branch. ✓
- Drum-kit member destinations unchanged — Task 1 leaves `addDrumKit` alone; asserted in Task 5 Step 3 manual check.

**Placeholder scan:** no TBDs; every step has exact code or exact command. Defensive branches (AU picker cancel, empty library) have inline handlers. ✓

**Type consistency:** `DestinationSummary.make(for:in:trackID:)` signature is the same across Task 2's test and Task 4's call. `AddDestinationSheet(isInGroup:auInstruments:onCommit:onCancel:)` matches the invocation in Task 4 Step 2. The `commit(destination:)` method uses the `setEditedDestination(_:for:)` project method that already exists (seen in the current `TrackDestinationEditor.swift`). ✓

**Risks:**
- `AudioSampleLibrary.shared.sample(id:)` API naming — flagged in Task 2 Step 3. If the accessor has a different name, fix inline.
- `AudioInstrumentChoice.displayName` vs `audioComponentID.displayKey` — flagged in Task 3 Step 1.
- SwiftUI `.sheet` behavior on macOS — expect a window-style sheet, not an iOS-style bottom sheet. Acceptable; the modal doesn't need bottom-sheet behavior. If it renders too small, the `minWidth: 420, minHeight: 320` frame modifier handles it.
