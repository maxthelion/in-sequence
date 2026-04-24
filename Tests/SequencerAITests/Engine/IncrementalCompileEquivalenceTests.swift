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
}
