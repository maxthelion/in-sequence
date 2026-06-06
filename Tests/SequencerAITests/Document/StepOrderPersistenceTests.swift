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

    func test_compilerRejectsDecodedStepOrderMapsWithOutOfRangeValues() throws {
        var project = Project.empty
        project.phrases[0].lengthBars = 1
        project.stepOrderMaps = [StepOrderMap(id: mapID, name: "Invalid", values: remapValues)]
        project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: true)
        var object = try JSONObject(from: project)
        object["stepOrderMaps"] = [
            [
                "id": mapID.uuidString,
                "name": "Invalid",
                "values": [0, 1, 2, 3, 4, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        let snapshot = SequencerSnapshotCompiler.compile(project: decoded)
        let phraseBuffer = try XCTUnwrap(snapshot.phraseBuffer(for: decoded.selectedPhraseID))

        XCTAssertEqual(decoded.stepOrderMaps[0].values[5], 16)
        XCTAssertEqual(decoded.stepOrderMaps[0].validationIssue, .outOfRange(values: [16]))
        XCTAssertNil(phraseBuffer.stepOrderMap)
        XCTAssertEqual(phraseBuffer.sourceStepIndex(for: 5), 5)
    }

    func test_decodedWrongLengthStepOrderMapLoadsButDoesNotCompileActiveMap() throws {
        var project = Project.empty
        project.phrases[0].lengthBars = 1
        project.stepOrderMaps = [StepOrderMap(id: mapID, name: "Short", values: StepOrderMap.identityValues)]
        project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: true)
        var object = try JSONObject(from: project)
        object["stepOrderMaps"] = [
            [
                "id": mapID.uuidString,
                "name": "Short",
                "values": [3, 2, 1]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        let snapshot = SequencerSnapshotCompiler.compile(project: decoded)
        let phraseBuffer = try XCTUnwrap(snapshot.phraseBuffer(for: decoded.selectedPhraseID))

        XCTAssertEqual(decoded.stepOrderMaps[0].values, [3, 2, 1])
        XCTAssertEqual(decoded.stepOrderMaps[0].validationIssue, .wrongLength(actual: 3))
        XCTAssertNil(phraseBuffer.stepOrderMap)
        XCTAssertEqual(phraseBuffer.sourceStepIndex(for: 2), 2)
    }

    func test_decodedNumericallyCorruptStepOrderMapLoadsAsInvalidQuarantine() throws {
        let json = """
        {
          "id": "\(mapID.uuidString)",
          "name": "Corrupt",
          "values": [0,1,2,300,4,5,6,7,8,9,10,11,12,13,14,15]
        }
        """

        let decoded = try JSONDecoder().decode(StepOrderMap.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.values, [])
        XCTAssertEqual(decoded.validationIssue, .wrongLength(actual: 0))
        XCTAssertNil(decoded.validatedCompiledValues)
    }

    func test_projectHelpers_rejectInvalidStepOrderMapCreationAndUpdate() {
        var project = Project.empty

        project.appendStepOrderMap(StepOrderMap(id: mapID, name: "Short", values: [0, 1, 2]))
        XCTAssertNil(project.stepOrderMap(id: mapID))

        project.appendStepOrderMap(StepOrderMap(id: mapID, name: "Valid", values: StepOrderMap.identityValues))
        XCTAssertEqual(project.stepOrderMap(id: mapID)?.values, StepOrderMap.identityValues)

        var invalidValues = StepOrderMap.identityValues
        invalidValues[4] = 16
        project.setStepOrderMapValues(id: mapID, values: invalidValues)
        XCTAssertEqual(project.stepOrderMap(id: mapID)?.values, StepOrderMap.identityValues)

        project.setStepOrderMapValues(id: mapID, values: remapValues)
        XCTAssertEqual(project.stepOrderMap(id: mapID)?.values, remapValues)
    }

    func test_projectHelpers_deleteOnlyUnusedStepOrderMapsWithBlockedReason() {
        var project = Project.empty
        project.stepOrderMaps = [
            StepOrderMap(id: mapID, name: "Assigned"),
            StepOrderMap(id: secondMapID, name: "Unused")
        ]
        project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: false)

        let assignedStatus = project.stepOrderMapDeletionStatus(id: mapID)
        XCTAssertFalse(assignedStatus.canDelete)
        XCTAssertEqual(assignedStatus.assignmentCount, 1)
        XCTAssertEqual(assignedStatus.assignedPhraseIDs, [project.phrases[0].id])
        XCTAssertEqual(assignedStatus.blockedReason, .assignedToPhrases(count: 1))
        XCTAssertFalse(project.deleteUnusedStepOrderMap(id: mapID))
        XCTAssertNotNil(project.stepOrderMap(id: mapID))

        let unusedStatus = project.stepOrderMapDeletionStatus(id: secondMapID)
        XCTAssertTrue(unusedStatus.canDelete)
        XCTAssertNil(unusedStatus.blockedReason)
        XCTAssertTrue(project.deleteUnusedStepOrderMap(id: secondMapID))
        XCTAssertNil(project.stepOrderMap(id: secondMapID))
    }

    func test_compilerResolvesMissingDeletedDisabledUnassignedAndUnsupportedStepOrderStatesToSequential() throws {
        var project = Project.empty
        project.phrases[0].lengthBars = 1
        project.stepOrderMaps = [
            StepOrderMap(id: mapID, name: "Break Fold", values: remapValues)
        ]

        project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: secondMapID, isEnabled: true)
        assertCompiledStepOrderIsSequential(project)

        project.stepOrderMaps.removeAll()
        project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: true)
        assertCompiledStepOrderIsSequential(project)

        project.stepOrderMaps = [StepOrderMap(id: mapID, name: "Break Fold", values: remapValues)]
        project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: false)
        assertCompiledStepOrderIsSequential(project)

        project.phrases[0].stepOrderAssignment = nil
        assertCompiledStepOrderIsSequential(project)

        project.phrases[0].lengthBars = 2
        project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: true)
        assertCompiledStepOrderIsSequential(project)
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
                Project.empty
            },
            edit: { session, _ in
                XCTAssertTrue(session.appendStepOrderMap(StepOrderMap(id: mapID, name: "Created", values: remapValues)))
            },
            assertStaleDocument: { project in
                XCTAssertNil(project.stepOrderMap(id: mapID))
            },
            assertFlushedProject: { project in
                XCTAssertEqual(project.stepOrderMap(id: mapID)?.values, remapValues)
            }
        )

        try assertStepOrderEditFlushes(
            makeProject: {
                Project.empty
            },
            edit: { session, _ in
                XCTAssertFalse(session.appendStepOrderMap(StepOrderMap(id: mapID, name: "Invalid", values: [0, 1, 2])))
            },
            assertStaleDocument: { project in
                XCTAssertNil(project.stepOrderMap(id: mapID))
            },
            assertFlushedProject: { project in
                XCTAssertNil(project.stepOrderMap(id: mapID))
            }
        )

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
                project.stepOrderMaps = [StepOrderMap(id: mapID, name: "Assigned")]
                project.phrases[0].stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: false)
                return project
            },
            edit: { session, _ in
                let status = session.stepOrderMapDeletionStatus(id: mapID)
                XCTAssertFalse(status.canDelete)
                XCTAssertEqual(status.assignmentCount, 1)
                XCTAssertEqual(status.blockedReason, .assignedToPhrases(count: 1))
                XCTAssertFalse(session.deleteUnusedStepOrderMap(id: mapID))
            },
            assertStaleDocument: { project in
                XCTAssertNotNil(project.stepOrderMap(id: mapID))
            },
            assertFlushedProject: { project in
                XCTAssertNotNil(project.stepOrderMap(id: mapID))
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

        try assertStepOrderEditFlushes(
            makeProject: {
                var project = Project.empty
                project.stepOrderMaps = [StepOrderMap(id: mapID, name: "Reject Invalid", values: StepOrderMap.identityValues)]
                return project
            },
            edit: { session, project in
                var invalidValues = remapValues
                invalidValues[0] = 99
                XCTAssertFalse(session.setStepOrderMapValues(id: mapID, values: invalidValues))
                XCTAssertEqual(session.stepOrderMapDeletionStatus(id: mapID).canDelete, true)
            },
            assertStaleDocument: { project in
                XCTAssertEqual(project.stepOrderMap(id: mapID)?.values, StepOrderMap.identityValues)
            },
            assertFlushedProject: { project in
                XCTAssertEqual(project.stepOrderMap(id: mapID)?.values, StepOrderMap.identityValues)
            }
        )
    }

    private func assertCompiledStepOrderIsSequential(
        _ project: Project,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        guard let phraseBuffer = snapshot.phraseBuffer(for: project.selectedPhraseID) else {
            XCTFail("Expected selected phrase buffer", file: file, line: line)
            return
        }
        XCTAssertNil(phraseBuffer.stepOrderMap, file: file, line: line)
        XCTAssertEqual(phraseBuffer.sourceStepIndex(for: 0), 0, file: file, line: line)
        XCTAssertEqual(phraseBuffer.sourceStepIndex(for: 5), 5, file: file, line: line)
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
