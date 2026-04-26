import XCTest
@testable import SequencerAI

final class MasterBusStateTests: XCTestCase {
    func test_defaultProject_hasCleanMasterBusScene() {
        let project = Project.empty

        XCTAssertEqual(project.masterBus.scenes.count, 1)
        XCTAssertEqual(project.masterBus.activeScene.name, "Clean")
        XCTAssertFalse(project.masterBus.hasUnsavedDraft)
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

    func test_draftCommitAndSaveAs() {
        var state = MasterBusState.default
        state.addInsert(.filter())

        XCTAssertTrue(state.hasUnsavedDraft)
        XCTAssertEqual(state.liveScene.inserts.count, 1)
        XCTAssertEqual(state.activeScene.inserts.count, 0)

        state.commitDraft(name: "Warm")
        XCTAssertFalse(state.hasUnsavedDraft)
        XCTAssertEqual(state.activeScene.name, "Warm")
        XCTAssertEqual(state.activeScene.inserts.count, 1)

        state.addInsert(.bitcrusher())
        state.saveDraftAsNewScene(name: "Crush")
        XCTAssertEqual(state.scenes.count, 2)
        XCTAssertEqual(state.activeScene.name, "Crush")
        XCTAssertEqual(state.activeScene.inserts.count, 2)
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
