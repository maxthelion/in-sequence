import SwiftUI
import XCTest
@testable import SequencerAI

/// Capture-harness protocol for the perform-overview dashboard: the status
/// file reports `performOverviewRowCount` so QA rows can assert the dashboard
/// collapsed kit members into single rows (wireframes §9 + §1). This pins the
/// exact status key the runner emits and that its value tracks the row model.
@MainActor
final class PerformOverviewHarnessProtocolTests: XCTestCase {

    private final class DocumentBox {
        var document: SeqAIDocument
        init(_ document: SeqAIDocument) { self.document = document }
    }

    private struct Fixture {
        let box: DocumentBox
        let engine: EngineController
        let session: SequencerDocumentSession
        let expectedRowCount: Int
    }

    /// Two ungrouped instrument tracks plus a three-member drum kit group:
    /// the row model collapses the kit to ONE row, so the harness must report
    /// 3 rows, not the 5 underlying tracks.
    private func makeFixture() -> Fixture {
        let groupID = UUID()

        func makeTrack(_ name: String, type: TrackType = .monoMelodic, group: TrackGroupID? = nil) -> StepSequenceTrack {
            StepSequenceTrack(
                name: name,
                trackType: type,
                pitches: [60],
                stepPattern: Array(repeating: false, count: 16),
                stepAccents: Array(repeating: false, count: 16),
                destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
                groupID: group,
                velocity: 96,
                gateLength: 4
            )
        }

        let lead = makeTrack("Lead")
        let pad = makeTrack("Pad", type: .polyMelodic)
        let kick = makeTrack("Kick", group: groupID)
        let snare = makeTrack("Snare", group: groupID)
        let hat = makeTrack("Hat", group: groupID)
        let tracks = [lead, pad, kick, snare, hat]
        let group = TrackGroup(id: groupID, name: "Kit", memberIDs: [kick.id, snare.id, hat.id])

        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        )

        let project = Project(
            version: 1,
            tracks: tracks,
            trackGroups: [group],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [],
            selectedTrackID: lead.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        let box = DocumentBox(SeqAIDocument(project: project))
        let engine = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()

        let expected = PerformOverviewRowModel.rows(
            tracks: session.store.tracks,
            groups: session.store.trackGroups
        ).count

        return Fixture(box: box, engine: engine, session: session, expectedRowCount: expected)
    }

    private func statusDictionary(fixture: Fixture) throws -> [String: String] {
        let statusURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perform-overview-harness-tests-\(UUID().uuidString).status")
        defer { try? FileManager.default.removeItem(at: statusURL) }

        VisualScenarioCommandRunner.writeStatus(
            to: statusURL,
            section: .tracks,
            visualPhraseControlsOpenIndex: nil,
            session: fixture.session,
            engineController: fixture.engine
        )

        let payload = try String(contentsOf: statusURL)
        return payload
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { result, rawLine in
                let line = String(rawLine).trimmingCharacters(in: .whitespaces)
                guard let separator = line.firstIndex(of: "=") else { return }
                result[String(line[..<separator])] =
                    String(line[line.index(after: separator)...])
            }
    }

    func test_statusEmitsPerformOverviewRowCountKey() throws {
        let fixture = makeFixture()
        let status = try statusDictionary(fixture: fixture)

        XCTAssertNotNil(
            status["performOverviewRowCount"],
            "the runner must emit a performOverviewRowCount status key"
        )
    }

    func test_performOverviewRowCount_collapsesKitMembersIntoOneRow() throws {
        let fixture = makeFixture()
        XCTAssertEqual(fixture.session.store.tracks.count, 5, "fixture has 5 underlying tracks")
        XCTAssertEqual(fixture.expectedRowCount, 3, "2 ungrouped instruments + 1 collapsed kit row")

        let status = try statusDictionary(fixture: fixture)
        XCTAssertEqual(
            status["performOverviewRowCount"],
            "3",
            "the harness row count must match the collapsed row model, not the raw track count"
        )
    }
}
