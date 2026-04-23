import XCTest
@testable import SequencerAI

// Phase 1a guardrail tests — authored-state ownership of LiveSequencerStore.
// These must fail before the implementation, pass after.

@MainActor
final class LiveSequencerStoreResidentStateTests: XCTestCase {

    // MARK: - 1. importFromProject detaches state

    func test_importFromProject_detachesState() {
        let (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let store = LiveSequencerStore(project: project)

        // Mutate via the store.
        store.mutateClip(id: clipID) { entry in
            entry.content = .noteGrid(
                lengthSteps: 1,
                steps: [ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]),
                    fill: nil
                )]
            )
        }

        // The original project value is independent of the store.
        XCTAssertEqual(project.clipPool.first(where: { $0.id == clipID })?.pitchPool, [60])
        let exported = store.exportToProject()
        XCTAssertEqual(exported.clipPool.first(where: { $0.id == clipID })?.pitchPool, [72])
    }

    // MARK: - 2. mutateClip changes only that clip

    func test_mutateClip_changesOnlyThatClip() {
        let trackID2 = UUID()
        let clipID2 = UUID()
        let project = makeMultiClipProject(
            extraTrackID: trackID2,
            extraClipID: clipID2
        )
        let store = LiveSequencerStore(project: project)
        let before = store.exportToProject()

        let targetClipID = before.clipPool[0].id
        let changed = store.mutateClip(id: targetClipID) { entry in
            entry.name = "Renamed"
        }

        XCTAssertTrue(changed)
        let after = store.exportToProject()

        // Only the mutated clip differs.
        let beforeOther = before.clipPool.first(where: { $0.id == clipID2 })
        let afterOther = after.clipPool.first(where: { $0.id == clipID2 })
        XCTAssertEqual(beforeOther, afterOther, "Unmutated clip should be byte-equal")

        // The mutated clip differs.
        let beforeTarget = before.clipPool.first(where: { $0.id == targetClipID })
        let afterTarget = after.clipPool.first(where: { $0.id == targetClipID })
        XCTAssertNotEqual(beforeTarget, afterTarget)
        XCTAssertEqual(afterTarget?.name, "Renamed")

        // Everything else should be identical.
        XCTAssertEqual(before.tracks, after.tracks)
        XCTAssertEqual(before.phrases, after.phrases)
        XCTAssertEqual(before.patternBanks, after.patternBanks)
        XCTAssertEqual(before.generatorPool, after.generatorPool)
        XCTAssertEqual(before.selectedTrackID, after.selectedTrackID)
        XCTAssertEqual(before.selectedPhraseID, after.selectedPhraseID)
    }

    // MARK: - 3. mutateTrack changes only that track

    func test_mutateTrack_changesOnlyThatTrack() {
        let project = makeTwoTrackProject()
        let store = LiveSequencerStore(project: project)
        let before = store.exportToProject()

        let targetTrackID = before.tracks[0].id
        let otherTrackID = before.tracks[1].id

        let changed = store.mutateTrack(id: targetTrackID) { track in
            track.name = "Edited Track"
        }

        XCTAssertTrue(changed)
        let after = store.exportToProject()

        XCTAssertEqual(after.tracks.first(where: { $0.id == targetTrackID })?.name, "Edited Track")
        XCTAssertEqual(
            before.tracks.first(where: { $0.id == otherTrackID }),
            after.tracks.first(where: { $0.id == otherTrackID }),
            "Unmutated track should be byte-equal"
        )

        // Other top-level fields should be identical.
        XCTAssertEqual(before.clipPool, after.clipPool)
        XCTAssertEqual(before.phrases, after.phrases)
        XCTAssertEqual(before.generatorPool, after.generatorPool)
    }

    // MARK: - 4. mutatePhrase changes only that phrase

    func test_mutatePhrase_changesOnlyThatPhrase() {
        let project = makeTwoPhraseProject()
        let store = LiveSequencerStore(project: project)
        let before = store.exportToProject()

        guard before.phrases.count >= 2 else {
            XCTFail("Expected at least 2 phrases")
            return
        }

        let targetPhraseID = before.phrases[0].id
        let otherPhraseID = before.phrases[1].id

        let changed = store.mutatePhrase(id: targetPhraseID) { phrase in
            phrase.name = "Edited Phrase"
        }

        XCTAssertTrue(changed)
        let after = store.exportToProject()

        XCTAssertEqual(after.phrases.first(where: { $0.id == targetPhraseID })?.name, "Edited Phrase")
        XCTAssertEqual(
            before.phrases.first(where: { $0.id == otherPhraseID }),
            after.phrases.first(where: { $0.id == otherPhraseID }),
            "Unmutated phrase should be byte-equal"
        )

        // Other top-level fields should be identical.
        XCTAssertEqual(before.tracks, after.tracks)
        XCTAssertEqual(before.clipPool, after.clipPool)
        XCTAssertEqual(before.generatorPool, after.generatorPool)
    }

    // MARK: - 5. mutateGenerator changes only that generator

    func test_mutateGenerator_changesOnlyThatGenerator() {
        let (project, _, _) = makeLiveStoreProject(clipPitch: 60)
        let store = LiveSequencerStore(project: project)
        let before = store.exportToProject()

        guard before.generatorPool.count >= 2 else {
            XCTFail("Expected at least 2 generators in pool")
            return
        }

        let targetGenID = before.generatorPool[0].id
        let otherGenID = before.generatorPool[1].id

        let changed = store.mutateGenerator(id: targetGenID) { entry in
            entry.name = "Renamed Generator"
        }

        XCTAssertTrue(changed)
        let after = store.exportToProject()

        XCTAssertEqual(after.generatorPool.first(where: { $0.id == targetGenID })?.name, "Renamed Generator")
        XCTAssertEqual(
            before.generatorPool.first(where: { $0.id == otherGenID }),
            after.generatorPool.first(where: { $0.id == otherGenID }),
            "Unmutated generator should be byte-equal"
        )

        XCTAssertEqual(before.tracks, after.tracks)
        XCTAssertEqual(before.clipPool, after.clipPool)
        XCTAssertEqual(before.phrases, after.phrases)
    }

    // MARK: - 6. setPatternBank changes only affected track

    func test_setPatternBank_changesOnlyAffectedTrack() {
        let project = makeTwoTrackProject()
        let store = LiveSequencerStore(project: project)
        let before = store.exportToProject()

        let targetTrackID = before.tracks[0].id
        let otherTrackID = before.tracks[1].id

        // Use a generator that's already in the pool so the attachedGeneratorID
        // survives Project normalization (which validates against generatorPool).
        let compatibleGenID = before.generatorPool.first(where: { $0.trackType == .monoMelodic })?.id

        var newBank = before.patternBanks.first(where: { $0.trackID == targetTrackID })
            ?? TrackPatternBank(trackID: targetTrackID, slots: [])
        // Only mutate the attachedGeneratorID; leave slots unchanged.
        newBank = TrackPatternBank(
            trackID: newBank.trackID,
            slots: newBank.slots,
            attachedGeneratorID: compatibleGenID
        )

        store.setPatternBank(trackID: targetTrackID, bank: newBank)
        let after = store.exportToProject()

        // Other track's bank unchanged.
        let beforeOtherBank = before.patternBanks.first(where: { $0.trackID == otherTrackID })
        let afterOtherBank = after.patternBanks.first(where: { $0.trackID == otherTrackID })
        XCTAssertEqual(beforeOtherBank, afterOtherBank, "Unaffected track bank should be byte-equal")

        // Target track's bank changed.
        let beforeTargetBank = before.patternBanks.first(where: { $0.trackID == targetTrackID })
        let afterTargetBank = after.patternBanks.first(where: { $0.trackID == targetTrackID })
        XCTAssertNotEqual(beforeTargetBank, afterTargetBank)
        XCTAssertEqual(afterTargetBank?.attachedGeneratorID, compatibleGenID)

        XCTAssertEqual(before.tracks, after.tracks)
        XCTAssertEqual(before.clipPool, after.clipPool)
    }

    // MARK: - 7. selection setters bump revision only on change

    func test_selectionSetters_bumpRevision() {
        let project = makeTwoTrackProject()
        let store = LiveSequencerStore(project: project)
        let exported = store.exportToProject()

        let trackA = exported.tracks[0].id
        let trackB = exported.tracks[1].id
        let phraseA = exported.phrases[0].id

        // Pre-condition: store's selectedTrackID should equal something.
        // Set to trackA first to ensure we know the starting value.
        store.setSelectedTrackID(trackA)
        let revAfterFirstSet = store.revision

        // Setting to the same value should NOT bump revision.
        store.setSelectedTrackID(trackA)
        XCTAssertEqual(store.revision, revAfterFirstSet, "Revision must not bump when value does not change")

        // Setting to a different value SHOULD bump revision.
        store.setSelectedTrackID(trackB)
        XCTAssertEqual(store.revision, revAfterFirstSet + 1, "Revision must bump when selectedTrackID changes")

        // Same pattern for selectedPhraseID.
        store.setSelectedPhraseID(phraseA)
        let revAfterPhraseSet = store.revision
        store.setSelectedPhraseID(phraseA)
        XCTAssertEqual(store.revision, revAfterPhraseSet, "Revision must not bump for same phraseID")
    }

    // MARK: - 8. roundtrip preserves full project

    func test_roundtrip_preservesFullProject() {
        let project = makeRichProject()
        let store = LiveSequencerStore(project: project)
        let exported = store.exportToProject()

        XCTAssertEqual(exported.version, project.version)
        XCTAssertEqual(exported.tracks, project.tracks)
        XCTAssertEqual(exported.trackGroups, project.trackGroups)
        XCTAssertEqual(exported.generatorPool, project.generatorPool)
        XCTAssertEqual(exported.clipPool, project.clipPool)
        XCTAssertEqual(exported.layers, project.layers)
        XCTAssertEqual(exported.routes, project.routes)
        XCTAssertEqual(exported.patternBanks, project.patternBanks)
        XCTAssertEqual(exported.selectedTrackID, project.selectedTrackID)
        XCTAssertEqual(exported.phrases, project.phrases)
        XCTAssertEqual(exported.selectedPhraseID, project.selectedPhraseID)
        XCTAssertEqual(exported, project, "Full Project roundtrip must be identity")
    }

    // MARK: - 9. mutate does not rewrite full Project

    func test_mutate_doesNotRewriteFullProject() {
        let project = makeMultiClipProject(extraTrackID: UUID(), extraClipID: UUID())
        let store = LiveSequencerStore(project: project)
        let before = store.exportToProject()

        let targetClipID = before.clipPool[0].id

        store.mutateClip(id: targetClipID) { entry in
            entry.name = "Only This Changed"
        }

        let after = store.exportToProject()

        // Enumerate all top-level differences. Only clipPool should differ.
        let differences = topLevelDiffs(lhs: before, rhs: after)
        XCTAssertEqual(differences, ["clipPool"],
            "Expected exactly [clipPool] to differ; got: \(differences)")
    }

    // MARK: - 10. mutateProject bridge still works

    func test_mutateProject_bridge_stillWorks() {
        let (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let store = LiveSequencerStore(project: project)
        let revBefore = store.revision

        let changed = store.mutateProject(impact: .snapshotOnly) { p in
            guard let index = p.clipPool.firstIndex(where: { $0.id == clipID }) else { return }
            p.clipPool[index].name = "BridgeRenamed"
        }

        XCTAssertTrue(changed)
        XCTAssertEqual(store.revision, revBefore + 1, "Revision must bump on bridge mutation")
        XCTAssertEqual(store.exportToProject().clipPool.first(where: { $0.id == clipID })?.name, "BridgeRenamed")
    }

    // MARK: - Helpers

    /// Returns the names of top-level fields that differ between two Project values.
    private func topLevelDiffs(lhs: Project, rhs: Project) -> Set<String> {
        var diffs = Set<String>()
        if lhs.version != rhs.version { diffs.insert("version") }
        if lhs.tracks != rhs.tracks { diffs.insert("tracks") }
        if lhs.trackGroups != rhs.trackGroups { diffs.insert("trackGroups") }
        if lhs.generatorPool != rhs.generatorPool { diffs.insert("generatorPool") }
        if lhs.clipPool != rhs.clipPool { diffs.insert("clipPool") }
        if lhs.layers != rhs.layers { diffs.insert("layers") }
        if lhs.routes != rhs.routes { diffs.insert("routes") }
        if lhs.patternBanks != rhs.patternBanks { diffs.insert("patternBanks") }
        if lhs.selectedTrackID != rhs.selectedTrackID { diffs.insert("selectedTrackID") }
        if lhs.phrases != rhs.phrases { diffs.insert("phrases") }
        if lhs.selectedPhraseID != rhs.selectedPhraseID { diffs.insert("selectedPhraseID") }
        return diffs
    }
}

// MARK: - Test project factories

private func makeMultiClipProject(extraTrackID: UUID, extraClipID: UUID) -> Project {
    let (project, _, _) = makeLiveStoreProject(clipPitch: 60)
    // Append a second clip to the pool directly.
    var rich = project
    let extra = ClipPoolEntry(
        id: extraClipID,
        name: "Extra Clip",
        trackType: .monoMelodic,
        content: .noteGrid(
            lengthSteps: 4,
            steps: [
                ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 64, velocity: 90, lengthSteps: 2)]), fill: nil),
                .empty, .empty, .empty,
            ]
        )
    )
    rich.clipPool.append(extra)
    return rich
}

private func makeTwoTrackProject() -> Project {
    let trackID1 = UUID()
    let trackID2 = UUID()
    let clipID1 = UUID()
    let clipID2 = UUID()

    let track1 = StepSequenceTrack(
        id: trackID1,
        name: "Track One",
        pitches: [60],
        stepPattern: [true, false, true, false],
        velocity: 100,
        gateLength: 4
    )
    let track2 = StepSequenceTrack(
        id: trackID2,
        name: "Track Two",
        pitches: [64],
        stepPattern: [false, true, false, true],
        velocity: 90,
        gateLength: 4
    )
    let clip1 = ClipPoolEntry(
        id: clipID1,
        name: "Clip One",
        trackType: .monoMelodic,
        content: .emptyNoteGrid(lengthSteps: 4)
    )
    let clip2 = ClipPoolEntry(
        id: clipID2,
        name: "Clip Two",
        trackType: .monoMelodic,
        content: .emptyNoteGrid(lengthSteps: 4)
    )
    let bank1 = TrackPatternBank(
        trackID: trackID1,
        slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clipID1))]
    )
    let bank2 = TrackPatternBank(
        trackID: trackID2,
        slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clipID2))]
    )
    let tracks = [track1, track2]
    let layers = PhraseLayerDefinition.defaultSet(for: tracks)
    let phrase = PhraseModel.default(tracks: tracks, layers: layers)
    return Project(
        version: 1,
        tracks: tracks,
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: [clip1, clip2],
        layers: layers,
        routes: [],
        patternBanks: [bank1, bank2],
        selectedTrackID: trackID1,
        phrases: [phrase],
        selectedPhraseID: phrase.id
    )
}

private func makeTwoPhraseProject() -> Project {
    let (base, _, _) = makeLiveStoreProject(clipPitch: 60)
    var project = base
    let tracks = project.tracks
    let layers = project.layers
    var second = PhraseModel.default(tracks: tracks, layers: layers)
    second.id = UUID()
    second.name = "Phrase B"
    project.phrases.append(second.synced(with: tracks, layers: layers))
    return project
}

/// A rich project exercising: multiple tracks, sampler filter, AU preset destination,
/// macro bindings with macro lanes, multiple clips, multiple phrases, multiple pattern banks
/// with clip/generator/modifier slot refs.
private func makeRichProject() -> Project {
    let trackID = UUID()
    let clipID1 = UUID()
    let clipID2 = UUID()
    let genID = UUID()
    let bindingID = UUID()

    let binding = TrackMacroBinding(
        descriptor: TrackMacroDescriptor(
            id: bindingID,
            displayName: "Test Macro",
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 42, identifier: "TestParam")
        )
    )
    let filter = SamplerFilterSettings(
        type: .lowpass,
        poles: .two,
        cutoffHz: 8_000,
        resonance: 0.25,
        drive: 0.1
    )
    let stateBlob = "hello".data(using: .utf8)
    let destination = Destination.auInstrument(
        componentID: AudioComponentID(type: "aumu", subtype: "test", manufacturer: "Test", version: 1),
        stateBlob: stateBlob
    )
    let track = StepSequenceTrack(
        id: trackID,
        name: "Rich Track",
        pitches: [60, 64, 67],
        stepPattern: Array(repeating: true, count: 16),
        destination: destination,
        velocity: 100,
        gateLength: 4,
        macros: [binding],
        filter: filter
    )
    let macroLane = MacroLane(values: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8,
                                       0.9, 1.0, 0.8, 0.6, 0.4, 0.2, 0.1, 0.3])
    let clip1 = ClipPoolEntry(
        id: clipID1,
        name: "Note Grid Clip",
        trackType: .monoMelodic,
        content: .noteGrid(
            lengthSteps: 16,
            steps: (0..<16).map { i in
                i % 2 == 0
                    ? ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60 + i, velocity: 100, lengthSteps: 1)]), fill: nil)
                    : .empty
            }
        ),
        macroLanes: [bindingID: macroLane]
    )
    let clip2 = ClipPoolEntry(
        id: clipID2,
        name: "Slice Clip",
        trackType: .slice,
        content: .sliceTriggers(
            stepPattern: [true, false, false, true, false, false, true, false],
            sliceIndexes: [0, 1, 2]
        )
    )
    let generator = GeneratorPoolEntry.makeDefault(
        id: genID,
        name: "Rich Gen",
        kind: .monoGenerator,
        trackType: .monoMelodic
    )
    let slot0 = TrackPatternSlot(
        slotIndex: 0,
        sourceRef: SourceRef(mode: .clip, clipID: clipID1, modifierGeneratorID: genID, modifierBypassed: false)
    )
    let slot1 = TrackPatternSlot(
        slotIndex: 1,
        sourceRef: SourceRef(mode: .generator, generatorID: genID, modifierGeneratorID: genID, modifierBypassed: true)
    )
    let bank = TrackPatternBank(trackID: trackID, slots: [slot0, slot1])
    let layers = PhraseLayerDefinition.defaultSet(for: [track])
    let phrase1 = PhraseModel.default(tracks: [track], layers: layers)
    var phrase2 = PhraseModel(id: UUID(), name: "Phrase B", lengthBars: 4, stepsPerBar: 16, cells: [])
    phrase2 = phrase2.synced(with: [track], layers: layers)

    var pool = GeneratorPoolEntry.defaultPool
    pool.append(generator)

    return Project(
        version: 1,
        tracks: [track],
        generatorPool: pool,
        clipPool: [clip1, clip2],
        layers: layers,
        routes: [],
        patternBanks: [bank],
        selectedTrackID: trackID,
        phrases: [phrase1, phrase2],
        selectedPhraseID: phrase1.id
    )
}
