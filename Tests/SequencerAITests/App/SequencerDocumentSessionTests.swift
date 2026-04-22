import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class SequencerDocumentSessionTests: XCTestCase {
    func test_flushToDocument_writes_pending_live_clip_edits() {
        let track = StepSequenceTrack(
            name: "Track",
            pitches: [60],
            stepPattern: [true],
            velocity: 100,
            gateLength: 4
        )
        let clip = ClipPoolEntry(
            id: UUID(),
            name: "Clip",
            trackType: track.trackType,
            content: .stepSequence(stepPattern: [false], pitches: [60])
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, clipPool: [clip])
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

        var document = SeqAIDocument(project: project)
        let binding = Binding(
            get: { document },
            set: { document = $0 }
        )
        let session = SequencerDocumentSession(
            document: binding,
            engineController: EngineController(client: nil, endpoint: nil)
        )

        session.updateClipContent(id: clip.id, content: .stepSequence(stepPattern: [true], pitches: [60]))

        XCTAssertEqual(document.project.clipEntry(id: clip.id)?.content, .stepSequence(stepPattern: [false], pitches: [60]))

        session.flushToDocument()

        XCTAssertEqual(document.project.clipEntry(id: clip.id)?.content, .stepSequence(stepPattern: [true], pitches: [60]))
    }
}
