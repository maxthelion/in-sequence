import XCTest
@testable import SequencerAI

@MainActor
final class IncrementalCompileEquivalenceTests: XCTestCase {

    func test_clipChange_matchesFullCompileOracle() throws {
        let (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())

        store.mutateClip(id: clipID) { clip in
            clip.content = .noteGrid(
                lengthSteps: 1,
                steps: [ClipStep(
                    main: ClipLane(
                        chance: 1,
                        notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]
                    ),
                    fill: nil
                )]
            )
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .clip(clipID),
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_phraseChange_matchesFullCompileOracle() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())
        let phraseID = try XCTUnwrap(store.phrases.first?.id)
        let muteLayerID = try XCTUnwrap(store.layers.first(where: { $0.target == .mute })?.id)

        store.mutatePhrase(id: phraseID) { phrase in
            phrase.setCell(.single(.bool(true)), for: muteLayerID, trackID: trackID)
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .phrase(phraseID),
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_patternBankChange_matchesFullCompileOracle() throws {
        let (baseProject, trackID, clipID) = makeLiveStoreProject()
        let alternateClipID = UUID(uuidString: "99999999-2222-3333-4444-555555555555")!
        let alternateClip = ClipPoolEntry(
            id: alternateClipID,
            name: "Alt Clip",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [ClipStep(
                    main: ClipLane(
                        chance: 1,
                        notes: [ClipStepNote(pitch: 84, velocity: 100, lengthSteps: 4)]
                    ),
                    fill: nil
                )]
            )
        )

        var project = baseProject
        project.clipPool.append(alternateClip)
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())
        XCTAssertEqual(previous.clipEntry(id: clipID)?.pitchPool, [60])

        store.mutatePatternBank(trackID: trackID) { bank in
            bank.setSlot(
                TrackPatternSlot(slotIndex: 0, sourceRef: .clip(alternateClipID)),
                at: 0
            )
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .patternBank(trackID),
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_selectedPhraseChange_reusesExistingBuffers() throws {
        let (baseProject, _, _) = makeLiveStoreProject()
        var project = baseProject
        let originalPhraseID = project.selectedPhraseID
        project.duplicatePhrase(id: originalPhraseID)
        let phrase = try XCTUnwrap(project.phrases.last)
        project.selectedPhraseID = project.phrases[0].id
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())

        store.setSelectedPhraseID(phrase.id)

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .selectedPhrase,
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
        XCTAssertEqual(incremental.selectedPhraseID, phrase.id)
        XCTAssertEqual(incremental.clipBuffersByID, previous.clipBuffersByID)
        XCTAssertEqual(incremental.trackProgramsByTrackID, previous.trackProgramsByTrackID)
        XCTAssertEqual(incremental.phraseBuffersByID, previous.phraseBuffersByID)
    }

    func test_generatorChange_matchesFullCompileOracle() throws {
        let (project, _, _) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())
        let generatorID = try XCTUnwrap(store.generatorPool.first?.id)

        store.mutateGenerator(id: generatorID) { generator in
            generator.name = "Renamed Generator"
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .generator(generatorID),
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_trackMetadataChange_matchesFullCompileOracle() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())

        store.mutateTrack(id: trackID) { track in
            track.name = "Renamed Track"
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .track(trackID),
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_trackMacroShapeChange_matchesFullCompileOracle() throws {
        let (project, trackID, clipID) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())
        let binding = TrackMacroBinding(descriptor: Self.testMacroDescriptor())

        store.mutateTrack(id: trackID) { track in
            track.macros.append(binding)
        }

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .track(trackID),
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
        XCTAssertEqual(incremental.trackProgramsByTrackID[trackID]?.macroBindingIDs, [binding.id])
        XCTAssertEqual(incremental.clipBuffersByID[clipID]?.macroBindingOrder, [binding.id])
    }

    func test_layersChange_matchesFullCompileOracle() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())
        var layers = store.layers
        let muteIndex = try XCTUnwrap(layers.firstIndex(where: { $0.target == .mute }))
        layers[muteIndex].defaults[trackID] = .bool(true)

        store.setLayers(layers)

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .layers,
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_bulkChange_matchesFullCompileOracle() throws {
        let (project, trackID, clipID) = makeLiveStoreProject(clipPitch: 60)
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())
        let phraseID = try XCTUnwrap(store.phrases.first?.id)
        let muteLayerID = try XCTUnwrap(store.layers.first(where: { $0.target == .mute })?.id)

        store.mutateClip(id: clipID) { clip in
            clip.name = "Bulk Clip"
        }
        store.mutatePhrase(id: phraseID) { phrase in
            phrase.setCell(.single(.bool(true)), for: muteLayerID, trackID: trackID)
        }
        store.mutateTrack(id: trackID) { track in
            track.velocity = 80
        }

        let change = SnapshotChange.clip(clipID)
            .union(.phrase(phraseID))
            .union(.track(trackID))
        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: change,
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    func test_fullRebuildChange_matchesFullCompileOracle() throws {
        let (project, _, _) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let previous = SequencerSnapshotCompiler.compile(state: store.compileInput())

        store.importFromProject({
            var next = project
            next.appendTrack(trackType: .monoMelodic)
            return next
        }())

        let state = store.compileInput()
        let expected = SequencerSnapshotCompiler.compile(state: state)
        let incremental = SequencerSnapshotCompiler.compile(
            changed: .full,
            previous: previous,
            state: state
        )

        XCTAssertEqual(incremental, expected)
    }

    private static func testMacroDescriptor() -> TrackMacroDescriptor {
        TrackMacroDescriptor(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            displayName: "Test Macro",
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 7, identifier: "test")
        )
    }
}
