import SwiftUI
import XCTest
@testable import SequencerAI

/// Track-view IA W1, AC1.3: per-track FX insert chain — model + session surface.
///
/// These tests exercise the public mutation surface
/// (`SequencerDocumentSession+TrackFXInserts`) and the `TrackFXInsert` /
/// `StepSequenceTrack` model contracts. They deliberately do NOT start the
/// audio engine — engine wiring is covered by the engine-graph layer; these
/// guard the authored-state path so inert/duplicate state cannot enter a
/// document.
@MainActor
final class TrackFXInsertTests: XCTestCase {

    private final class DocumentBox {
        var document: SeqAIDocument
        init(document: SeqAIDocument) { self.document = document }
    }

    private func makeSession(project: Project) -> (SequencerDocumentSession, DocumentBox) {
        let box = DocumentBox(document: SeqAIDocument(project: project))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil)
        )
        return (session, box)
    }

    private func liveTrack(_ session: SequencerDocumentSession, _ trackID: UUID) throws -> StepSequenceTrack {
        let project = session.store.exportToProject()
        return try XCTUnwrap(project.tracks.first(where: { $0.id == trackID }))
    }

    // MARK: - Session surface: add / remove / reorder / bypass

    func test_addFXInsert_appendsToChain() throws {
        let (project, trackID, _) = makeLiveStoreProject(clipPitch: 60)
        let (session, _) = makeSession(project: project)

        XCTAssertTrue(session.addFXInsert(trackID: trackID, insert: .filter()))
        XCTAssertTrue(session.addFXInsert(trackID: trackID, insert: .bitcrusher()))

        let chain = try liveTrack(session, trackID).fxInserts
        XCTAssertEqual(chain.count, 2)
        XCTAssertEqual(chain.map(\.name), ["Filter", "Bitcrusher"])
    }

    func test_removeFXInsert_dropsByID() throws {
        let (project, trackID, _) = makeLiveStoreProject(clipPitch: 60)
        let (session, _) = makeSession(project: project)

        let filter = TrackFXInsert.filter()
        let crusher = TrackFXInsert.bitcrusher()
        session.addFXInsert(trackID: trackID, insert: filter)
        session.addFXInsert(trackID: trackID, insert: crusher)

        XCTAssertTrue(session.removeFXInsert(trackID: trackID, insertID: filter.id))

        let chain = try liveTrack(session, trackID).fxInserts
        XCTAssertEqual(chain.map(\.id), [crusher.id])
    }

    func test_moveFXInsert_reorders() throws {
        let (project, trackID, _) = makeLiveStoreProject(clipPitch: 60)
        let (session, _) = makeSession(project: project)

        let a = TrackFXInsert.filter()
        let b = TrackFXInsert.bitcrusher()
        session.addFXInsert(trackID: trackID, insert: a)
        session.addFXInsert(trackID: trackID, insert: b)

        // Move the first insert to the end.
        XCTAssertTrue(session.moveFXInsert(trackID: trackID, from: IndexSet(integer: 0), to: 2))

        let chain = try liveTrack(session, trackID).fxInserts
        XCTAssertEqual(chain.map(\.id), [b.id, a.id])
    }

    func test_setFXInsertBypassed_togglesFlag() throws {
        let (project, trackID, _) = makeLiveStoreProject(clipPitch: 60)
        let (session, _) = makeSession(project: project)

        let insert = TrackFXInsert.filter()
        session.addFXInsert(trackID: trackID, insert: insert)
        XCTAssertFalse(try liveTrack(session, trackID).fxInserts[0].bypassed)

        XCTAssertTrue(session.setFXInsertBypassed(trackID: trackID, insertID: insert.id, bypassed: true))
        XCTAssertTrue(try liveTrack(session, trackID).fxInserts[0].bypassed)

        XCTAssertTrue(session.setFXInsertBypassed(trackID: trackID, insertID: insert.id, bypassed: false))
        XCTAssertFalse(try liveTrack(session, trackID).fxInserts[0].bypassed)
    }

    func test_mutations_returnFalseForUnknownTrack() {
        let (project, _, _) = makeLiveStoreProject(clipPitch: 60)
        let (session, _) = makeSession(project: project)
        let unknown = UUID()

        XCTAssertFalse(session.addFXInsert(trackID: unknown, insert: .filter()))
        XCTAssertFalse(session.removeFXInsert(trackID: unknown, insertID: UUID()))
        XCTAssertFalse(session.setFXInsertBypassed(trackID: unknown, insertID: UUID(), bypassed: true))
    }

    // MARK: - normalizedChain reassigns colliding UUIDs

    func test_normalizedChain_reassignsCollidingUUIDs() {
        let shared = UUID()
        let a = TrackFXInsert(id: shared, name: "Filter", kind: .nativeFilter(.default))
        let b = TrackFXInsert(id: shared, name: "Bitcrusher", kind: .nativeBitcrusher(.default))

        let normalized = TrackFXInsert.normalizedChain([a, b])

        XCTAssertEqual(normalized.count, 2)
        XCTAssertEqual(normalized[0].id, shared, "First occurrence keeps its id")
        XCTAssertNotEqual(normalized[1].id, shared, "Collision must get a fresh id")
        XCTAssertEqual(Set(normalized.map(\.id)).count, 2, "Ids must be unique")
    }

    // MARK: - Empty name falls back to kind.defaultName

    func test_normalize_emptyName_usesKindDefaultName() {
        let blank = TrackFXInsert(name: "   ", kind: .nativeBitcrusher(.default))
        XCTAssertEqual(blank.normalized().name, "Bitcrusher")

        let blankFilter = TrackFXInsert(name: "", kind: .nativeFilter(.default))
        XCTAssertEqual(blankFilter.normalized().name, "Filter")
    }

    func test_addFXInsert_emptyName_persistsDefaultName() throws {
        let (project, trackID, _) = makeLiveStoreProject(clipPitch: 60)
        let (session, _) = makeSession(project: project)

        session.addFXInsert(trackID: trackID, insert: TrackFXInsert(name: "  ", kind: .nativeFilter(.default)))

        XCTAssertEqual(try liveTrack(session, trackID).fxInserts[0].name, "Filter")
    }

    // MARK: - Codable round-trip + legacy decode

    func test_trackFXInsert_codableRoundTrip() throws {
        let inserts: [TrackFXInsert] = [
            .filter(),
            TrackFXInsert(name: "Crush", bypassed: true, kind: .nativeBitcrusher(.default)),
            .auEffect(.testEffect),
        ]
        let data = try JSONEncoder().encode(inserts)
        let decoded = try JSONDecoder().decode([TrackFXInsert].self, from: data)
        XCTAssertEqual(decoded, inserts)
    }

    func test_track_withFXInserts_codableRoundTrip() throws {
        var track = StepSequenceTrack(
            name: "FX Track",
            pitches: [60],
            stepPattern: Array(repeating: true, count: 16),
            velocity: 100,
            gateLength: 4
        )
        track.fxInserts = [.filter(), TrackFXInsert(name: "Crush", bypassed: true, kind: .nativeBitcrusher(.default))]

        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(StepSequenceTrack.self, from: data)
        XCTAssertEqual(decoded.fxInserts, track.fxInserts)
    }

    /// Legacy documents predate the `fxInserts` key; they must decode to an
    /// empty chain (no inert state, no decode failure).
    func test_legacyTrack_missingFXInsertsKey_decodesToEmptyChain() throws {
        let track = StepSequenceTrack(
            name: "Legacy",
            pitches: [60],
            stepPattern: Array(repeating: true, count: 16),
            velocity: 100,
            gateLength: 4
        )
        let data = try JSONEncoder().encode(track)
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        json.removeValue(forKey: "fxInserts")
        XCTAssertNil(json["fxInserts"], "Precondition: fxInserts key removed")

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(StepSequenceTrack.self, from: legacyData)
        XCTAssertEqual(decoded.fxInserts, [], "Missing fxInserts must decode to an empty chain")
    }
}
