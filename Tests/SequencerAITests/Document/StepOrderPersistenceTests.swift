import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import SequencerAI

@MainActor
final class StepOrderPersistenceTests: XCTestCase {
    private final class DocumentBox {
        var document: SeqAIDocument

        init(project: Project) {
            self.document = SeqAIDocument(project: project)
        }

        var binding: Binding<SeqAIDocument> {
            Binding(get: { self.document }, set: { _ in })
        }
    }

    private let mapID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    private let secondMapID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let remapValues: [UInt8] = [0, 1, 2, 3, 3, 3, 3, 3, 7, 8, 9, 0, 1, 2, 3, 3]

    func test_projectCodableRoundTrip_preservesStepOrderMapPoolAndPhraseAssignment() throws {
        var project = Project.empty
        project.stepOrderMaps = [
            StepOrderMap(id: mapID, name: "Break Fold", values: remapValues)
        ]
        project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: true)

        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)

        XCTAssertEqual(decoded.stepOrderMaps, project.stepOrderMaps)
        XCTAssertEqual(decoded.stepOrderMaps[0].id, mapID)
        XCTAssertEqual(decoded.stepOrderMaps[0].name, "Break Fold")
        XCTAssertEqual(decoded.stepOrderMaps[0].values, remapValues)
        XCTAssertEqual(decoded.phrases[0].stepOrderAssignment, StepOrderAssignment(mapID: mapID, isEnabled: true))
    }

    func test_legacyProjectDecode_withoutStepOrderFields_defaultsToEmptyPoolAndSequentialPlayback() throws {
        var object = try JSONObject(from: Project.empty)
        object.removeValue(forKey: "stepOrderMaps")
        var phrases = try XCTUnwrap(object["phrases"] as? [[String: Any]])
        for index in phrases.indices {
            phrases[index].removeValue(forKey: "stepOrderAssignment")
        }
        object["phrases"] = phrases

        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        let snapshot = SequencerSnapshotCompiler.compile(project: decoded)
        let phraseBuffer = try XCTUnwrap(snapshot.phraseBuffer(for: decoded.selectedPhraseID))

        XCTAssertTrue(decoded.stepOrderMaps.isEmpty)
        XCTAssertNil(decoded.phrases[0].stepOrderAssignment)
        XCTAssertNil(phraseBuffer.stepOrderMap)
        XCTAssertEqual(phraseBuffer.sourceStepIndex(for: 0), 0)
        XCTAssertEqual(phraseBuffer.sourceStepIndex(for: 15), 15)
    }

    func test_compilerResolvesEnabledStepOrderAssignmentFromPersistedMapPool() throws {
        var project = Project.empty
        project.phrases[0].lengthBars = 1
        project.stepOrderMaps = [
            StepOrderMap(id: mapID, name: "Break Fold", values: remapValues)
        ]
        project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: true)

        var snapshot = SequencerSnapshotCompiler.compile(project: project)
        var phraseBuffer = try XCTUnwrap(snapshot.phraseBuffer(for: project.selectedPhraseID))
        XCTAssertEqual(phraseBuffer.stepOrderMap, remapValues)
        XCTAssertEqual(phraseBuffer.sourceStepIndex(for: 5), 3)

        project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: false)
        snapshot = SequencerSnapshotCompiler.compile(project: project)
        phraseBuffer = try XCTUnwrap(snapshot.phraseBuffer(for: project.selectedPhraseID))
        XCTAssertNil(phraseBuffer.stepOrderMap)
        XCTAssertEqual(phraseBuffer.sourceStepIndex(for: 5), 5)
    }

    func test_stepOrderMapValuesAreFixedToSixteenEntriesOnInitAndDecode() throws {
        let shortMap = StepOrderMap(id: mapID, name: "Short", values: [3, 2, 1])
        XCTAssertEqual(shortMap.values.count, 16)
        XCTAssertEqual(Array(shortMap.values.prefix(3)), [3, 2, 1])
        XCTAssertEqual(Array(shortMap.values.dropFirst(3)), Array(StepOrderMap.identityValues.dropFirst(3)))

        let json = """
        {
          "id": "\(mapID.uuidString)",
          "name": "Long",
          "values": [15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0,9,9]
        }
        """
        let decoded = try JSONDecoder().decode(StepOrderMap.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.values.count, 16)
        XCTAssertEqual(decoded.values, [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
    }

    func test_projectHelpers_deleteOnlyUnusedStepOrderMaps() {
        var project = Project.empty
        project.stepOrderMaps = [
            StepOrderMap(id: mapID, name: "Assigned"),
            StepOrderMap(id: secondMapID, name: "Unused")
        ]
        project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: false)

        XCTAssertFalse(project.deleteUnusedStepOrderMap(id: mapID))
        XCTAssertNotNil(project.stepOrderMap(id: mapID))
        XCTAssertTrue(project.deleteUnusedStepOrderMap(id: secondMapID))
        XCTAssertNil(project.stepOrderMap(id: secondMapID))
    }

    func test_codablePayloadDoesNotContainRuntimePendingStepOrderState() throws {
        var project = Project.empty
        project.stepOrderMaps = [StepOrderMap(id: mapID, name: "Persisted")]
        project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: true)

        let data = try JSONEncoder().encode(project)
        let payload = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(payload.contains("stepOrderMaps"))
        XCTAssertTrue(payload.contains("stepOrderAssignment"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("pending"))
    }

    func test_sessionDurableStepOrderEditsFlushThroughDocumentSnapshot() throws {
        try assertStepOrderEditFlushes(
            makeProject: {
                var project = Project.empty
                project.stepOrderMaps = [StepOrderMap(id: mapID, name: "Old", values: StepOrderMap.identityValues)]
                return project
            },
            edit: { session, project in
                session.setStepOrderMapValues(id: mapID, values: remapValues)
            },
            assertStaleDocument: { project in
                XCTAssertEqual(project.stepOrderMap(id: mapID)?.values, StepOrderMap.identityValues)
            },
            assertFlushedProject: { project in
                XCTAssertEqual(project.stepOrderMap(id: mapID)?.values, remapValues)
            }
        )

        try assertStepOrderEditFlushes(
            makeProject: {
                var project = Project.empty
                project.stepOrderMaps = [StepOrderMap(id: mapID, name: "Old Name")]
                return project
            },
            edit: { session, project in
                session.renameStepOrderMap(id: mapID, name: "New Name")
            },
            assertStaleDocument: { project in
                XCTAssertEqual(project.stepOrderMap(id: mapID)?.name, "Old Name")
            },
            assertFlushedProject: { project in
                XCTAssertEqual(project.stepOrderMap(id: mapID)?.name, "New Name")
            }
        )

        try assertStepOrderEditFlushes(
            makeProject: {
                var project = Project.empty
                project.stepOrderMaps = [StepOrderMap(id: mapID, name: "Assign")]
                return project
            },
            edit: { session, project in
                session.setStepOrderAssignment(phraseID: project.selectedPhraseID, mapID: mapID, isEnabled: false)
            },
            assertStaleDocument: { project in
                XCTAssertNil(project.selectedPhrase.stepOrderAssignment)
            },
            assertFlushedProject: { project in
                XCTAssertEqual(project.selectedPhrase.stepOrderAssignment, StepOrderAssignment(mapID: mapID, isEnabled: false))
            }
        )

        try assertStepOrderEditFlushes(
            makeProject: {
                var project = Project.empty
                project.stepOrderMaps = [StepOrderMap(id: mapID, name: "Delete")]
                return project
            },
            edit: { session, project in
                session.deleteUnusedStepOrderMap(id: mapID)
            },
            assertStaleDocument: { project in
                XCTAssertNotNil(project.stepOrderMap(id: mapID))
            },
            assertFlushedProject: { project in
                XCTAssertNil(project.stepOrderMap(id: mapID))
            }
        )

        try assertStepOrderEditFlushes(
            makeProject: {
                var project = Project.empty
                project.stepOrderMaps = [StepOrderMap(id: mapID, name: "Enable")]
                project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: false)
                return project
            },
            edit: { session, project in
                session.setPhraseStepOrderEnabled(true, phraseID: project.selectedPhraseID)
            },
            assertStaleDocument: { project in
                XCTAssertEqual(project.selectedPhrase.stepOrderAssignment?.isEnabled, false)
            },
            assertFlushedProject: { project in
                XCTAssertEqual(project.selectedPhrase.stepOrderAssignment?.isEnabled, true)
            }
        )
    }

    private func assertStepOrderEditFlushes(
        makeProject: () -> Project,
        edit: (SequencerDocumentSession, Project) -> Void,
        assertStaleDocument: (Project) -> Void,
        assertFlushedProject: (Project) -> Void
    ) throws {
        let project = makeProject()
        let box = DocumentBox(project: project)
        let session = SequencerDocumentSession(
            document: box.binding,
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .seconds(100)
        )
        defer {
            SequencerDocumentSessionRegistry.unregister(session)
        }

        edit(session, project)

        assertStaleDocument(box.document.project)
        let snapshotProject = try box.document.snapshot(contentType: .seqAIDocument)
        assertFlushedProject(box.document.project)
        assertFlushedProject(snapshotProject)
    }

    private func JSONObject(from project: Project) throws -> [String: Any] {
        let data = try JSONEncoder().encode(project)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
