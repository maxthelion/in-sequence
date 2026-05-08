import XCTest
@testable import SequencerAI

final class MasterBusStateTests: XCTestCase {
    func test_defaultProject_hasBlankSceneSlots() {
        let project = Project.empty

        XCTAssertEqual(project.masterBus.scenes.count, 2)
        XCTAssertEqual(project.masterBus.scenes.map(\.name), ["Scene A", "Scene B"])
        XCTAssertEqual(project.masterBus.activeScene.name, "Scene A")
        XCTAssertTrue(project.masterBus.activeScene.macroBindings.isEmpty)
        XCTAssertEqual(project.masterBus.abSelection?.sceneAID, project.masterBus.scenes[0].id)
        XCTAssertEqual(project.masterBus.abSelection?.sceneBID, project.masterBus.scenes[1].id)
        XCTAssertEqual(project.masterBus.masterOutputGain, 1)
    }

    func test_oldProjectJSONDecodesWithDefaultMasterBus() throws {
        let encoded = try JSONEncoder().encode(Project.empty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "masterBus")
        let oldData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Project.self, from: oldData)

        XCTAssertEqual(decoded.masterBus.scenes.count, 2)
        XCTAssertEqual(decoded.masterBus.activeScene.name, "Scene A")
        XCTAssertTrue(decoded.masterBus.scenes[0].inserts.isEmpty)
        XCTAssertNotNil(decoded.masterBus.abSelection)
    }

    func test_legacyMasterBusJSONDecodesWithUnityMasterOutputGain() throws {
        let encoded = try JSONEncoder().encode(MasterBusState.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "masterOutputGain")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(MasterBusState.self, from: legacyData)

        XCTAssertEqual(decoded.masterOutputGain, 1)
    }

    func test_masterOutputGainRoundTripsAndNormalizesToValidRange() throws {
        var state = MasterBusState.default
        state.setMasterOutputGain(1.75)

        let decoded = try JSONDecoder().decode(MasterBusState.self, from: try JSONEncoder().encode(state))

        XCTAssertEqual(decoded.masterOutputGain, 1.75)

        state.setMasterOutputGain(2.5)
        XCTAssertEqual(state.masterOutputGain, 2)

        state.setMasterOutputGain(-0.25)
        XCTAssertEqual(state.masterOutputGain, 0)
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

        XCTAssertEqual(state.scenes.count, 3)
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

    func test_sceneOutputGain_isNormalizedToUnityAndNotAMacroTarget() {
        let scene = MasterBusScene(
            name: "Gain",
            outputGain: 0.2,
            macroBindings: [MasterSceneMacroBinding(slotIndex: 0, target: .outputGain)]
        )

        let state = MasterBusState(scenes: [scene], activeSceneID: scene.id)

        XCTAssertEqual(state.activeScene.outputGain, 1)
        XCTAssertTrue(state.activeScene.macroBindings.isEmpty)
    }

    func test_auParameterMacroStoresAuthoredValueAndCleansUpWithInsert() {
        var state = MasterBusState.default
        let sceneID = state.activeSceneID
        let insert = MasterBusInsert.auEffect(.testEffect)
        state.addInsert(insert, sceneID: sceneID)
        let macro = MasterSceneMacroBinding(
            slotIndex: 0,
            target: .auParameter(
                insertID: insert.id,
                address: 3000,
                identifier: "3000",
                displayName: "Frequency",
                minValue: 10,
                maxValue: 20_000,
                defaultValue: 440,
                unit: "Hz"
            )
        )

        state.upsertMacroBinding(macro, sceneID: sceneID)
        state.setMacroValue(sceneID: sceneID, macroID: state.activeScene.macroBindings[0].id, value: 2_000)

        XCTAssertEqual(state.activeScene.macroBindings[0].name, "Codex Test Effect Frequency")
        XCTAssertEqual(state.activeScene.macroBindings[0].value(in: state.activeScene), 2_000)

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
        XCTAssertEqual(decoded.scenes.count, 2)
        XCTAssertNotNil(decoded.abSelection)
        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        XCTAssertNil(reencoded?["draftScene"])
    }

    func test_invalidABSelection_defaultsToFirstTwoScenes() {
        let scene = MasterBusScene.clean
        let missingID = UUID()
        let state = MasterBusState(
            scenes: [scene],
            activeSceneID: scene.id,
            abSelection: MasterBusABSelection(sceneAID: scene.id, sceneBID: missingID, crossfader: 2)
        )

        XCTAssertEqual(state.scenes.count, 2)
        XCTAssertEqual(state.abSelection?.sceneAID, state.scenes[0].id)
        XCTAssertEqual(state.abSelection?.sceneBID, state.scenes[1].id)
        XCTAssertEqual(state.abSelection?.crossfader, 1)
    }

    func test_removingScenes_keepsTwoABSlots() {
        var state = MasterBusState.default
        let addedID = state.addScene(name: "Third")

        state.removeScene(id: addedID)
        state.removeScene(id: state.scenes[0].id)

        XCTAssertEqual(state.scenes.count, 2)
        XCTAssertNotNil(state.abSelection)
    }
}
