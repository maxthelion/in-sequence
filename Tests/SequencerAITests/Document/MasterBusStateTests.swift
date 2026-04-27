import XCTest
@testable import SequencerAI

final class MasterBusStateTests: XCTestCase {
    func test_defaultProject_hasCleanMasterBusScene() {
        let project = Project.empty

        XCTAssertEqual(project.masterBus.scenes.count, 1)
        XCTAssertEqual(project.masterBus.activeScene.name, "Clean")
        XCTAssertTrue(project.masterBus.activeScene.macroBindings.isEmpty)
    }

    func test_oldProjectJSONDecodesWithDefaultMasterBus() throws {
        let encoded = try JSONEncoder().encode(Project.empty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "masterBus")
        let oldData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Project.self, from: oldData)

        XCTAssertEqual(decoded.masterBus.activeScene.name, "Clean")
        XCTAssertTrue(decoded.masterBus.scenes[0].inserts.isEmpty)
    }

    func test_auEffectStateBlob_roundTrips() throws {
        let blob = Data([1, 2, 3, 4])
        let componentID = AudioComponentID(type: "aufx", subtype: "TEST", manufacturer: "CDX ", version: 0)
        let insert = MasterBusInsert(
            name: "External",
            kind: .auEffect(componentID: componentID, stateBlob: blob)
        )
        let scene = MasterBusScene(name: "AU Scene", inserts: [insert])
        let project = Project(
            version: 1,
            tracks: Project.empty.tracks,
            clipPool: Project.empty.clipPool,
            layers: Project.empty.layers,
            masterBus: MasterBusState(scenes: [scene], activeSceneID: scene.id),
            patternBanks: Project.empty.patternBanks,
            selectedTrackID: Project.empty.selectedTrackID,
            phrases: Project.empty.phrases,
            selectedPhraseID: Project.empty.selectedPhraseID
        )

        let decoded = try JSONDecoder().decode(Project.self, from: try JSONEncoder().encode(project))

        guard case let .auEffect(_, decodedBlob)? = decoded.masterBus.activeScene.inserts.first?.kind else {
            return XCTFail("Expected AU effect insert")
        }
        XCTAssertEqual(decodedBlob, blob)
    }

    func test_directSceneEditingMutatesActiveScene() {
        var state = MasterBusState.default
        state.addInsert(.filter())

        XCTAssertEqual(state.activeScene.inserts.count, 1)

        let newSceneID = state.addScene(name: "Crush")
        state.addInsert(.bitcrusher(), sceneID: newSceneID)

        XCTAssertEqual(state.scenes.count, 2)
        XCTAssertEqual(state.activeScene.name, "Crush")
        XCTAssertEqual(state.activeScene.inserts.count, 1)
    }

    func test_macroBindingsAreCappedAndCleanedUpWhenInsertIsRemoved() {
        var state = MasterBusState.default
        let sceneID = state.activeSceneID
        let insert = MasterBusInsert.filter()
        state.addInsert(insert, sceneID: sceneID)

        for slot in 0..<12 {
            state.upsertMacroBinding(
                MasterSceneMacroBinding(slotIndex: slot, target: .filterCutoff(insertID: insert.id)),
                sceneID: sceneID
            )
        }

        XCTAssertEqual(state.activeScene.macroBindings.count, 8)

        state.removeInsert(id: insert.id, sceneID: sceneID)

        XCTAssertTrue(state.activeScene.macroBindings.isEmpty)
    }

    func test_legacyDraftPromotesIntoActiveSceneOnDecode() throws {
        struct LegacyMasterBusState: Encodable {
            let scenes: [MasterBusScene]
            let activeSceneID: UUID
            let draftScene: MasterBusScene
        }

        let active = MasterBusScene(id: MasterBusScene.cleanID, name: "Clean")
        let draft = MasterBusScene(id: UUID(), name: "Draft", inserts: [.filter()])
        let data = try JSONEncoder().encode(
            LegacyMasterBusState(
                scenes: [active],
                activeSceneID: active.id,
                draftScene: draft
            )
        )

        let decoded = try JSONDecoder().decode(MasterBusState.self, from: data)

        XCTAssertEqual(decoded.activeScene.id, active.id)
        XCTAssertEqual(decoded.activeScene.name, "Draft")
        XCTAssertEqual(decoded.activeScene.inserts.count, 1)
        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        XCTAssertNil(reencoded?["draftScene"])
    }

    func test_invalidABSelection_isNormalizedAway() {
        let scene = MasterBusScene.clean
        let missingID = UUID()
        let state = MasterBusState(
            scenes: [scene],
            activeSceneID: scene.id,
            abSelection: MasterBusABSelection(sceneAID: scene.id, sceneBID: missingID, crossfader: 2)
        )

        XCTAssertNil(state.abSelection)
    }
}
