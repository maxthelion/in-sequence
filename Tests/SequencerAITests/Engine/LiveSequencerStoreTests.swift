import XCTest
@testable import SequencerAI

@MainActor
final class LiveSequencerStoreTests: XCTestCase {
    func test_updateClipContent_and_phraseCell_mutate_live_project() {
        let fixture = makeFixtureProject()
        let store = LiveSequencerStore(project: fixture.project)

        store.updateClipContent(
            id: fixture.clip.id,
            content: .stepSequence(stepPattern: [true, true], pitches: [60, 62])
        )
        store.setPhraseCell(
            .single(.bool(true)),
            layerID: fixture.muteLayer.id,
            trackIDs: [fixture.track.id],
            phraseID: fixture.phrase.id
        )

        XCTAssertEqual(store.project.clipEntry(id: fixture.clip.id)?.content, .stepSequence(stepPattern: [true, true], pitches: [60, 62]))
        XCTAssertEqual(
            store.project.phrases.first?.cell(for: fixture.muteLayer.id, trackID: fixture.track.id),
            .single(.bool(true))
        )
        XCTAssertEqual(store.projectToProject(base: .empty), store.project)
    }

    private func makeFixtureProject() -> (project: Project, track: StepSequenceTrack, clip: ClipPoolEntry, phrase: PhraseModel, muteLayer: PhraseLayerDefinition) {
        let track = StepSequenceTrack(
            name: "Track",
            pitches: [60, 62],
            stepPattern: [true, false],
            velocity: 100,
            gateLength: 4
        )
        let clip = ClipPoolEntry(
            id: UUID(),
            name: "Clip",
            trackType: track.trackType,
            content: .stepSequence(stepPattern: [false, true], pitches: [60, 62])
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let muteLayer = layers.first(where: { $0.target == .mute })!
        let phrase = PhraseModel(
            id: UUID(),
            name: "Phrase",
            lengthBars: 1,
            stepsPerBar: 2,
            cells: layers.map { PhraseCellAssignment(trackID: track.id, layerID: $0.id, cell: .inheritDefault) }
        )
        let bank = TrackPatternBank(
            trackID: track.id,
            slots: (0..<TrackPatternBank.slotCount).map {
                TrackPatternSlot(slotIndex: $0, sourceRef: .clip($0 == 0 ? clip.id : nil))
            }
        )
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip],
            layers: layers,
            patternBanks: [bank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        return (project, track, clip, phrase, muteLayer)
    }
}
