import XCTest
@testable import SequencerAI

final class MasterBusStateTests: XCTestCase {
    func test_defaultProject_hasBlankSceneSlots() {
        let project = Project.empty

        XCTAssertEqual(project.masterBus.scenes.count, 2)
        // Default scenes are named "1"/"2" since the scene-perform visual fix
        // (913b5510) renamed the A/B seeds to numerals.
        XCTAssertEqual(project.masterBus.scenes.map(\.name), ["1", "2"])
        XCTAssertEqual(project.masterBus.activeScene.name, "1")
        XCTAssertTrue(project.masterBus.activeScene.macroBindings.isEmpty)
        XCTAssertEqual(project.masterBus.abSelection?.sceneAID, project.masterBus.scenes[0].id)
        XCTAssertEqual(project.masterBus.abSelection?.sceneBID, project.masterBus.scenes[1].id)
        XCTAssertEqual(project.masterBus.masterOutputGain, 1)
        XCTAssertTrue(project.masterBus.masterInserts.isEmpty)
    }

    func test_defaultProject_hasFixedEmptySendBuses() {
        let project = Project.empty

        XCTAssertEqual(project.sendBusA.id, .sendA)
        XCTAssertEqual(project.sendBusA.name, "Send A")
        XCTAssertTrue(project.sendBusA.inserts.isEmpty)
        XCTAssertEqual(project.sendBusB.id, .sendB)
        XCTAssertEqual(project.sendBusB.name, "Send B")
        XCTAssertTrue(project.sendBusB.inserts.isEmpty)
        XCTAssertEqual(project.selectedTrack.mix.sendA, 0)
        XCTAssertEqual(project.selectedTrack.mix.sendB, 0)
    }

    func test_oldProjectJSONDecodesWithDefaultMasterBus() throws {
        let encoded = try JSONEncoder().encode(Project.empty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "masterBus")
        let oldData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Project.self, from: oldData)

        XCTAssertEqual(decoded.masterBus.scenes.count, 2)
        XCTAssertEqual(decoded.masterBus.activeScene.name, "1")
        XCTAssertTrue(decoded.masterBus.scenes[0].inserts.isEmpty)
        XCTAssertNotNil(decoded.masterBus.abSelection)
    }

    func test_legacyMasterBusJSONDecodesWithUnityMasterOutputGain() throws {
        let encoded = try JSONEncoder().encode(MasterBusState.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "masterOutputGain")
        object.removeValue(forKey: "masterInserts")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(MasterBusState.self, from: legacyData)

        XCTAssertEqual(decoded.masterOutputGain, 1)
        XCTAssertTrue(decoded.masterInserts.isEmpty)
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

    func test_masterInsertsRoundTripAsPostBlendBusState() throws {
        let sceneA = MasterBusScene(name: "A", inserts: [.filter()])
        let sceneB = MasterBusScene(name: "B", inserts: [.bitcrusher()])
        var state = MasterBusState(scenes: [sceneA, sceneB], activeSceneID: sceneA.id)
        let insert = MasterBusInsert.filter()

        state.addMasterInsert(insert)
        state.updateMasterInsert(id: insert.id) { $0.isEnabled = false }

        let decoded = try JSONDecoder().decode(MasterBusState.self, from: try JSONEncoder().encode(state))

        XCTAssertEqual(decoded.masterInserts.count, 1)
        XCTAssertEqual(decoded.masterInserts[0].id, insert.id)
        XCTAssertFalse(decoded.masterInserts[0].isEnabled)
        XCTAssertEqual(decoded.scene(id: sceneA.id)?.inserts.count, 1)
        XCTAssertEqual(decoded.scene(id: sceneB.id)?.inserts.count, 1)
    }

    func test_authoredOutOfRangeMasterOutputGainDecodesNormalizedWithoutLosingState() throws {
        let sceneAID = UUID()
        let sceneBID = UUID()
        let sceneA = MasterBusScene(id: sceneAID, name: "Intro Loop", inserts: [.filter()])
        let sceneB = MasterBusScene(id: sceneBID, name: "Breakdown", inserts: [.bitcrusher()])
        let state = MasterBusState(
            scenes: [sceneA, sceneB],
            activeSceneID: sceneBID,
            abSelection: MasterBusABSelection(sceneAID: sceneAID, sceneBID: sceneBID, crossfader: 0.75),
            masterOutputGain: 1
        )

        let highDecoded = try decodePersisted(state, overridingMasterOutputGainWith: 2.5)
        let lowDecoded = try decodePersisted(state, overridingMasterOutputGainWith: -0.25)

        XCTAssertEqual(highDecoded.masterOutputGain, 2)
        XCTAssertEqual(lowDecoded.masterOutputGain, 0)

        for decoded in [highDecoded, lowDecoded] {
            XCTAssertEqual(decoded.scenes, state.scenes)
            XCTAssertEqual(decoded.activeSceneID, sceneBID)
            XCTAssertEqual(decoded.activeScene.name, "Breakdown")
            XCTAssertEqual(decoded.activeScene.inserts, sceneB.inserts)
            XCTAssertEqual(decoded.abSelection, state.abSelection)
        }
    }

    @MainActor
    func test_masterMeterStateIsRuntimeOnlyAndAbsentFromProjectCodableState() throws {
        let project = Project.empty
        let publisher = MasterMeterPublisher()
        publisher.recordPeakAmplitudes(left: 1.5, right: 0.25)
        publisher.publishPendingToMain(now: 1)

        let encoded = try JSONEncoder().encode(project)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let masterBus = try XCTUnwrap(object["masterBus"] as? [String: Any])

        XCTAssertTrue(publisher.displayState.isClipLatched)
        XCTAssertNil(masterBus["meter"])
        XCTAssertNil(masterBus["masterMeter"])
        XCTAssertNil(masterBus["clipLatched"])
        XCTAssertNil(masterBus["leftPeakDBFS"])
        XCTAssertNil(masterBus["rightPeakDBFS"])
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

    func test_addSceneCopyFrom_duplicatesInsertsAndRemapsMacroBindings() throws {
        var state = MasterBusState.default
        let sourceID = state.activeSceneID
        let filter = MasterBusInsert.filter()
        state.addInsert(filter, sceneID: sourceID)
        state.upsertMacroBinding(
            MasterSceneMacroBinding(slotIndex: 0, target: .filterCutoff(insertID: filter.id)),
            sceneID: sourceID
        )

        let newSceneID = state.addScene(copyFrom: sourceID)

        let source = try XCTUnwrap(state.scene(id: sourceID))
        let copy = try XCTUnwrap(state.scene(id: newSceneID))
        XCTAssertEqual(state.scenes.count, 3)
        XCTAssertEqual(copy.name, "\(source.name) Copy")
        XCTAssertEqual(state.activeSceneID, newSceneID)

        // Inserts are value copies under fresh IDs; the source is untouched.
        XCTAssertEqual(copy.inserts.count, 1)
        let copiedInsert = try XCTUnwrap(copy.inserts.first)
        XCTAssertNotEqual(copiedInsert.id, filter.id)
        XCTAssertEqual(copiedInsert.kind, filter.kind)
        XCTAssertEqual(source.inserts.map(\.id), [filter.id])

        // Macro bindings are remapped onto the duplicated insert IDs so they
        // stay valid inside the new scene.
        XCTAssertEqual(copy.macroBindings.count, 1)
        guard case let .filterCutoff(remappedInsertID) = try XCTUnwrap(copy.macroBindings.first).target else {
            return XCTFail("Expected a filterCutoff macro target")
        }
        XCTAssertEqual(remappedInsertID, copiedInsert.id)
    }

    func test_addSceneCopyFrom_missingSource_fallsBackToFreshScene() {
        var state = MasterBusState.default

        let newSceneID = state.addScene(copyFrom: UUID())

        XCTAssertEqual(state.scenes.count, 3)
        XCTAssertTrue(state.scene(id: newSceneID)?.inserts.isEmpty == true)
        XCTAssertEqual(state.activeSceneID, newSceneID)
    }

    func test_insertSceneCopy_remapsIdentityWithoutChangingActiveOrABSelection() throws {
        var state = MasterBusState.default
        let activeSceneID = state.activeSceneID
        let abSelection = try XCTUnwrap(state.abSelection)
        let insert = MasterBusInsert.filter()
        let snapshot = MasterBusScene(
            name: "Detached",
            inserts: [insert],
            macroBindings: [
                MasterSceneMacroBinding(slotIndex: 0, target: .filterCutoff(insertID: insert.id))
            ]
        )

        let pastedID = state.insertSceneCopy(of: snapshot)

        let pasted = try XCTUnwrap(state.scene(id: pastedID))
        let pastedInsert = try XCTUnwrap(pasted.inserts.first)
        let pastedBinding = try XCTUnwrap(pasted.macroBindings.first)
        XCTAssertNotEqual(pasted.id, snapshot.id)
        XCTAssertNotEqual(pastedInsert.id, insert.id)
        XCTAssertNotEqual(pastedBinding.id, snapshot.macroBindings[0].id)
        guard case let .filterCutoff(targetInsertID) = pastedBinding.target else {
            return XCTFail("Expected a filterCutoff macro target")
        }
        XCTAssertEqual(targetInsertID, pastedInsert.id)
        XCTAssertEqual(state.activeSceneID, activeSceneID)
        XCTAssertEqual(state.abSelection, abSelection)
    }

    func test_removingScenes_keepsTwoABSlots() {
        var state = MasterBusState.default
        let addedID = state.addScene(name: "Third")

        state.removeScene(id: addedID)
        state.removeScene(id: state.scenes[0].id)

        XCTAssertEqual(state.scenes.count, 2)
        XCTAssertNotNil(state.abSelection)
    }

    func test_legacyProjectJSONDecodesWithoutMixerBusesRoutingOrSolo() throws {
        let encoded = try JSONEncoder().encode(Project.empty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "buses")
        object.removeValue(forKey: "sendBusA")
        object.removeValue(forKey: "sendBusB")
        var tracks = try XCTUnwrap(object["tracks"] as? [[String: Any]])
        for index in tracks.indices {
            tracks[index].removeValue(forKey: "outputBusID")
            var mix = try XCTUnwrap(tracks[index]["mix"] as? [String: Any])
            mix.removeValue(forKey: "isSoloed")
            mix.removeValue(forKey: "sendA")
            mix.removeValue(forKey: "sendB")
            tracks[index]["mix"] = mix
        }
        object["tracks"] = tracks
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Project.self, from: legacyData)

        XCTAssertTrue(decoded.buses.isEmpty)
        XCTAssertEqual(decoded.sendBusA, .sendA)
        XCTAssertEqual(decoded.sendBusB, .sendB)
        XCTAssertNil(decoded.selectedTrack.outputBusID)
        XCTAssertFalse(decoded.selectedTrack.mix.isSoloed)
        XCTAssertEqual(decoded.selectedTrack.mix.sendA, 0)
        XCTAssertEqual(decoded.selectedTrack.mix.sendB, 0)
    }

    func test_mixerBusRoutingAndSoloStateRoundTrips() throws {
        var project = Project.empty
        let busID = project.addMixerBus(name: " Drum Stem ", color: " blue ")
        project.setTrackOutputBus(trackID: project.selectedTrackID, busID: busID)
        project.setTrackSoloed(true, trackID: project.selectedTrackID)
        project.tracks[project.selectedTrackIndex].mix.sendA = 0.35
        project.tracks[project.selectedTrackIndex].mix.sendB = 1.4
        project.setSendBusInserts([.filter()], id: .sendA)
        project.setSendBusInserts([.bitcrusher()], id: .sendB)
        project.updateMixerBusMix(id: busID) { mix in
            mix.level = 0.62
            mix.pan = -0.25
            mix.isMuted = true
            mix.isSoloed = true
        }
        project.buses[0].inserts = [.filter()]

        let decoded = try JSONDecoder().decode(Project.self, from: try JSONEncoder().encode(project))

        XCTAssertEqual(decoded.buses.count, 1)
        XCTAssertEqual(decoded.buses[0].id, busID)
        XCTAssertEqual(decoded.buses[0].name, "Drum Stem")
        XCTAssertEqual(decoded.buses[0].color, "blue")
        XCTAssertEqual(decoded.buses[0].mix, BusMixSettings(level: 0.62, pan: -0.25, isMuted: true, isSoloed: true))
        XCTAssertEqual(decoded.buses[0].inserts.count, 1)
        XCTAssertEqual(decoded.selectedTrack.outputBusID, busID)
        XCTAssertTrue(decoded.selectedTrack.mix.isSoloed)
        XCTAssertEqual(decoded.selectedTrack.mix.sendA, 0.35)
        XCTAssertEqual(decoded.selectedTrack.mix.sendB, 1)
        XCTAssertEqual(decoded.sendBusA.id, .sendA)
        XCTAssertEqual(decoded.sendBusA.name, "Send A")
        XCTAssertEqual(decoded.sendBusA.inserts.count, 1)
        XCTAssertEqual(decoded.sendBusB.id, .sendB)
        XCTAssertEqual(decoded.sendBusB.name, "Send B")
        XCTAssertEqual(decoded.sendBusB.inserts.count, 1)
    }

    func test_trackMixSendValuesClampOnAuthoredWritesAndDecode() throws {
        var mix = TrackMixSettings.default
        mix.sendA = -0.25
        mix.sendB = 2

        XCTAssertEqual(mix.sendA, 0)
        XCTAssertEqual(mix.sendB, 1)

        let encoded = try JSONEncoder().encode(TrackMixSettings.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["sendA"] = 1.5
        object["sendB"] = -0.2
        let decoded = try JSONDecoder().decode(
            TrackMixSettings.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.sendA, 1)
        XCTAssertEqual(decoded.sendB, 0)
    }

    func test_trackMixSceneMembership_defaultsToBothForLegacyJSON() throws {
        let encoded = try JSONEncoder().encode(TrackMixSettings.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "sceneMembership")

        let decoded = try JSONDecoder().decode(
            TrackMixSettings.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.sceneMembership, .both)
    }

    /// WS6 AC3 (353829be hard line): scene membership is a SEPARATE axis from
    /// the Send A/B levels — assigning membership must leave the send values
    /// (and their persisted encoding) byte-identical, and the spec default is
    /// membership BOTH (current behavior preserved).
    func test_trackMixSceneMembership_leavesSendValuesByteIdentical() throws {
        XCTAssertEqual(TrackMixSettings.default.sceneMembership, .both)

        var mix = TrackMixSettings(level: 0.8, pan: 0.1, isMuted: false, sendA: 0.33, sendB: 0.44)
        let sendBytesBefore = try sendFieldBytes(of: mix)

        mix.sceneMembership = .sceneB

        XCTAssertEqual(mix.sendA, 0.33)
        XCTAssertEqual(mix.sendB, 0.44)
        XCTAssertEqual(try sendFieldBytes(of: mix), sendBytesBefore)

        let roundTripped = try JSONDecoder().decode(
            TrackMixSettings.self,
            from: JSONEncoder().encode(mix)
        )
        XCTAssertEqual(roundTripped.sendA, 0.33)
        XCTAssertEqual(roundTripped.sendB, 0.44)
        XCTAssertEqual(roundTripped.sceneMembership, .sceneB)
        XCTAssertEqual(mix.normalized(), mix)
    }

    private func sendFieldBytes(of mix: TrackMixSettings) throws -> Data {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(mix)) as? [String: Any]
        )
        let sends: [String: Any] = object.filter { $0.key == "sendA" || $0.key == "sendB" }
        return try JSONSerialization.data(withJSONObject: sends, options: [.sortedKeys])
    }

    func test_trackMixSceneMembershipGain_usesEqualPowerCrossfader() {
        XCTAssertEqual(TrackMixSettings.SceneMembership.sceneA.gain(crossfader: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(TrackMixSettings.SceneMembership.sceneA.gain(crossfader: 1), 0, accuracy: 0.0001)
        XCTAssertEqual(TrackMixSettings.SceneMembership.sceneB.gain(crossfader: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(TrackMixSettings.SceneMembership.sceneB.gain(crossfader: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(TrackMixSettings.SceneMembership.both.gain(crossfader: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(TrackMixSettings.SceneMembership.both.gain(crossfader: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(
            TrackMixSettings.SceneMembership.sceneA.gain(crossfader: 0.5),
            TrackMixSettings.SceneMembership.sceneB.gain(crossfader: 0.5),
            accuracy: 0.0001
        )
    }

    private func decodePersisted(
        _ state: MasterBusState,
        overridingMasterOutputGainWith masterOutputGain: Double
    ) throws -> MasterBusState {
        let encoded = try JSONEncoder().encode(state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["masterOutputGain"] = masterOutputGain
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(MasterBusState.self, from: data)
    }
}
