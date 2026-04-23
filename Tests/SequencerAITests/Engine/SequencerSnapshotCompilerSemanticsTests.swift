import XCTest
@testable import SequencerAI

final class SequencerSnapshotCompilerSemanticsTests: XCTestCase {
    func test_compiler_uses_note_grid_and_exact_step_pattern_selection() throws {
        let macroDescriptor = TrackMacroDescriptor.builtin(
            trackID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            kind: .sampleGain
        )
        let binding = TrackMacroBinding(descriptor: macroDescriptor)
        var (project, trackID, clipID) = makeLiveStoreProject(clipPitch: 60, macros: [binding])

        project.updateClipEntry(id: clipID) { entry in
            entry.macroLanes[binding.id] = MacroLane(values: [nil, 0.75])
        }
        project.setPhraseCell(
            .steps([.index(0), .index(1)]),
            layerID: "pattern",
            trackIDs: [trackID],
            phraseID: project.selectedPhraseID
        )

        let altClipID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
        project.clipPool.append(
            ClipPoolEntry(
                id: altClipID,
                name: "Alt",
                trackType: .monoMelodic,
                content: .noteGrid(
                    lengthSteps: 2,
                    steps: [
                        ClipStep(main: ClipLane(chance: 0.5, notes: [ClipStepNote(pitch: 72, velocity: 91, lengthSteps: 5)]), fill: nil),
                        .empty
                    ]
                )
            )
        )
        project.setPatternClipID(altClipID, for: trackID, slotIndex: 1)

        let snapshot = SequencerSnapshotCompiler.compile(project: project)

        let clipBuffer = try XCTUnwrap(snapshot.clipBuffersByID[clipID])
        XCTAssertEqual(clipBuffer.steps.first?.main?.notes.first?.pitch, 60)
        XCTAssertEqual(clipBuffer.macroOverrides(at: 1)[binding.id], 0.75)

        let phraseBuffer = try XCTUnwrap(snapshot.phraseBuffersByID[project.selectedPhraseID])
        let trackState = try XCTUnwrap(phraseBuffer.trackState(for: trackID))
        XCTAssertEqual(Array(trackState.patternSlotIndex.prefix(2)), [0, 1])
    }
}
