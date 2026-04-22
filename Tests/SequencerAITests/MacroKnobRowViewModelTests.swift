import XCTest
@testable import SequencerAI

/// Tests for `MacroKnobRowViewModel` — the pure logic layer of the live macro
/// knob row. Verifies that `applyLiveValue` writes to the phrase layer default
/// without touching any phrase cells.
final class MacroKnobRowViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeProject() -> (Project, TrackMacroBinding) {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack

        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Sample Gain",
            minValue: -60,
            maxValue: 12,
            defaultValue: 0,
            valueType: .scalar,
            source: .builtin(.sampleGain)
        )
        let binding = TrackMacroBinding(descriptor: descriptor)

        // Attach binding to the selected (newly appended) track.
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == track.id }) else {
            XCTFail("selected track not found"); return (project, binding)
        }
        project.tracks[trackIndex].macros = [binding]
        project.syncMacroLayers()

        return (project, binding)
    }

    // MARK: - currentValue

    func test_currentValue_returnsDescriptorDefault_whenNoLayerDefault() {
        let (project, binding) = makeProject()
        let viewModel = MacroKnobRowViewModel()
        let trackID = project.selectedTrackID

        let value = viewModel.currentValue(binding: binding, trackID: trackID, project: project)
        XCTAssertEqual(value, binding.descriptor.defaultValue, accuracy: 0.001)
    }

    func test_currentValue_returnsLayerDefault_whenSet() {
        var (project, binding) = makeProject()
        let trackID = project.selectedTrackID

        // Set the layer default directly.
        project.setMacroLayerDefault(
            value: -6.0,
            bindingID: binding.id,
            trackID: trackID,
            phraseID: project.selectedPhraseID
        )

        let viewModel = MacroKnobRowViewModel()
        let value = viewModel.currentValue(binding: binding, trackID: trackID, project: project)
        XCTAssertEqual(value, -6.0, accuracy: 0.001)
    }

    // MARK: - applyLiveValue

    func test_applyLiveValue_writesToLayerDefault_notToPhraseCells() {
        var (project, binding) = makeProject()
        let trackID = project.selectedTrackID
        let phraseID = project.selectedPhraseID
        let layerID = "macro-\(trackID.uuidString)-\(binding.id.uuidString)"

        let cellsBefore = project.phrases
            .first(where: { $0.id == phraseID })?
            .cells.filter { $0.layerID == layerID } ?? []

        var viewModel = MacroKnobRowViewModel()
        viewModel.applyLiveValue(-3.0, binding: binding, trackID: trackID, project: &project)

        // Layer default is set.
        let layerDefault = project.layers
            .first(where: { $0.id == layerID })?
            .defaults[trackID]
        XCTAssertEqual(layerDefault, .scalar(-3.0))

        // No new phrase cells were created.
        let cellsAfter = project.phrases
            .first(where: { $0.id == phraseID })?
            .cells.filter { $0.layerID == layerID } ?? []
        XCTAssertEqual(cellsBefore.count, cellsAfter.count,
            "applyLiveValue must not add or modify phrase cells")
    }

    func test_applyLiveValue_doesNotCreatePhraseCells() {
        var (project, binding) = makeProject()
        let trackID = project.selectedTrackID
        let phraseID = project.selectedPhraseID
        let layerID = "macro-\(trackID.uuidString)-\(binding.id.uuidString)"

        // Capture cells count before.
        let cellsBefore = project.phrases
            .first(where: { $0.id == phraseID })?
            .cells.filter { $0.layerID == layerID && $0.trackID == trackID } ?? []

        var viewModel = MacroKnobRowViewModel()
        viewModel.applyLiveValue(-12.0, binding: binding, trackID: trackID, project: &project)

        let cellsAfter = project.phrases
            .first(where: { $0.id == phraseID })?
            .cells.filter { $0.layerID == layerID && $0.trackID == trackID } ?? []

        // applyLiveValue must not add new phrase cells.
        XCTAssertEqual(cellsBefore.count, cellsAfter.count,
            "applyLiveValue must not add or remove phrase cells")

        // Layer default is updated.
        let layerDefault = project.layers
            .first(where: { $0.id == layerID })?
            .defaults[trackID]
        XCTAssertEqual(layerDefault, .scalar(-12.0))
    }
}
