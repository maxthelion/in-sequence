import SwiftUI
import XCTest
@testable import SequencerAI

final class ProjectAssetPoolTests: XCTestCase {

    // MARK: - Codable

    func test_legacyDocument_decodesWithEmptyPool() throws {
        let encoded = try JSONEncoder().encode(Project.empty)
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json.removeValue(forKey: "assetPool")
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(Project.self, from: legacyData)
        XCTAssertTrue(decoded.assetPool.isEmpty)
    }

    func test_assetPool_roundTripsThroughCodable() throws {
        var project = Project.empty
        let sampleID = UUID()
        let kitID = UUID()
        project.addToAssetPool(kind: .sample, assetID: sampleID)
        project.addToAssetPool(kind: .drumKit, assetID: kitID)

        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)

        XCTAssertEqual(decoded.assetPool, project.assetPool)
        XCTAssertTrue(decoded.isInAssetPool(kind: .sample, assetID: sampleID))
        XCTAssertTrue(decoded.isInAssetPool(kind: .drumKit, assetID: kitID))
    }

    // MARK: - Project mutations

    func test_addToAssetPool_deduplicatesByKindAndID() {
        var project = Project.empty
        let assetID = UUID()

        XCTAssertTrue(project.addToAssetPool(kind: .sample, assetID: assetID))
        XCTAssertFalse(project.addToAssetPool(kind: .sample, assetID: assetID))
        XCTAssertEqual(project.assetPool.count, 1)

        // Same ID under a different kind is a distinct entry.
        XCTAssertTrue(project.addToAssetPool(kind: .drumKit, assetID: assetID))
        XCTAssertEqual(project.assetPool.count, 2)
    }

    func test_removeFromAssetPool_removesOnlyMatchingEntry() {
        var project = Project.empty
        let keep = UUID()
        let remove = UUID()
        project.addToAssetPool(kind: .sample, assetID: keep)
        project.addToAssetPool(kind: .sample, assetID: remove)

        XCTAssertTrue(project.removeFromAssetPool(kind: .sample, assetID: remove))
        XCTAssertFalse(project.removeFromAssetPool(kind: .sample, assetID: remove))
        XCTAssertEqual(project.pooledAssetIDs(kind: .sample), [keep])
    }

    func test_addThenRemove_restoresOriginalProject() {
        let original = Project.empty
        var project = original
        let assetID = UUID()

        project.addToAssetPool(kind: .patternTemplate, assetID: assetID)
        XCTAssertNotEqual(project, original)
        project.removeFromAssetPool(kind: .patternTemplate, assetID: assetID)
        XCTAssertEqual(project, original, "add → remove must be a perfect inverse (undo restores equality)")
    }

    // MARK: - Live store

    @MainActor
    func test_storePoolMutations_bumpRevisionAndExport() {
        let store = LiveSequencerStore(project: .empty)
        let assetID = UUID()

        let revisionBefore = store.revision
        XCTAssertTrue(store.addPooledAsset(PooledAssetRef(kind: .sample, assetID: assetID)))
        XCTAssertGreaterThan(store.revision, revisionBefore)
        XCTAssertEqual(store.exportToProject().assetPool.map(\.assetID), [assetID])

        XCTAssertFalse(store.addPooledAsset(PooledAssetRef(kind: .sample, assetID: assetID)), "duplicate add is a no-op")

        XCTAssertTrue(store.removePooledAsset(kind: .sample, assetID: assetID))
        XCTAssertTrue(store.exportToProject().assetPool.isEmpty)
        XCTAssertFalse(store.removePooledAsset(kind: .sample, assetID: assetID))
    }

    // MARK: - Session: undo path

    @MainActor
    func test_sessionPoolAddRemove_isUndoableViaExternalDocumentChange() {
        let box = DocumentBox(document: SeqAIDocument(project: .empty))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: box.binding,
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        let assetID = UUID()
        let before = session.store.exportToProject()

        XCTAssertTrue(session.addAssetToPool(kind: .drumKit, assetID: assetID))
        XCTAssertTrue(session.isAssetPooled(kind: .drumKit, assetID: assetID))
        session.flushToDocumentSync()
        XCTAssertEqual(box.document.project.assetPool.count, 1)

        // Undo arrives as an external document change (the document framework
        // restores a previous project value).
        session.ingestExternalDocumentChange(before)
        XCTAssertFalse(session.isAssetPooled(kind: .drumKit, assetID: assetID))
        XCTAssertEqual(session.store.exportToProject(), before)

        // Remove is equally invertible.
        XCTAssertTrue(session.addAssetToPool(kind: .drumKit, assetID: assetID))
        XCTAssertTrue(session.removeAssetFromPool(kind: .drumKit, assetID: assetID))
        XCTAssertEqual(session.store.exportToProject(), before)
    }

    @MainActor
    func test_sessionPoolMutations_doNotTouchLibraryFilesOnDisk() throws {
        // Pool membership is reference-only: the recordings directory of a
        // real library root must be byte-identical across add/remove.
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let library = RecordingLibrary(libraryRoot: tempRoot)
        let pcm = AudioInputCapturedPCM(
            sampleRate: 44_100,
            channels: [(0..<64).map { Float($0) / 64 }]
        )
        let asset = try library.storeRecording(pcm: pcm, sourceTrackName: "Mic", barCount: 1, bpm: 120)
        let contentsBefore = try FileManager.default.contentsOfDirectory(atPath: library.recordingsDirectory.path).sorted()

        let box = DocumentBox(document: SeqAIDocument(project: .empty))
        let session = SequencerDocumentSession(
            document: box.binding,
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .seconds(100)
        )
        XCTAssertTrue(session.addAssetToPool(kind: .sample, assetID: asset.id))
        XCTAssertTrue(session.removeAssetFromPool(kind: .sample, assetID: asset.id))

        let contentsAfter = try FileManager.default.contentsOfDirectory(atPath: library.recordingsDirectory.path).sorted()
        XCTAssertEqual(contentsAfter, contentsBefore)
        XCTAssertNotNil(library.recording(id: asset.id))
    }
}

private final class DocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }

    var binding: Binding<SeqAIDocument> {
        Binding(
            get: { self.document },
            set: { self.document = $0 }
        )
    }
}
