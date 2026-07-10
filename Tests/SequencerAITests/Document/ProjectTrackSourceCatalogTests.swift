import Foundation
import XCTest
@testable import SequencerAI

final class ProjectTrackSourceCatalogTests: XCTestCase {
    func test_generatedSourceInputClips_returns_entire_clip_pool() {
        let track = StepSequenceTrack.default
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [
                ClipPoolEntry(
                    id: UUID(),
                    name: "Mono",
                    trackType: .monoMelodic,
                    content: .stepSequence(stepPattern: [true, false], pitches: [60])
                ),
                ClipPoolEntry(
                    id: UUID(),
                    name: "Poly",
                    trackType: .polyMelodic,
                    content: .pianoRoll(
                        lengthBars: 1,
                        stepsPerBar: 16,
                        notes: [ClipNote(pitch: 65, startStep: 0, lengthSteps: 4, velocity: 100)]
                    )
                ),
                ClipPoolEntry(
                    id: UUID(),
                    name: "Drum",
                    trackType: .slice,
                    content: .sliceTriggers(stepPattern: [true, false, true, false], sliceIndexes: [0, 1, 0, 1], stepModes: [])
                ),
            ],
            layers: layers,
            routes: [],
            patternBanks: [TrackPatternBank.default(for: track, initialClipID: nil)],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        XCTAssertEqual(project.generatedSourceInputClips().map(\.id), project.clipPool.map(\.id))
    }

    func test_harmonicSidechainClips_returns_pitch_material_without_track_type_filtering() {
        let monoTrack = StepSequenceTrack.default
        let layers = PhraseLayerDefinition.defaultSet(for: [monoTrack])
        let phrase = PhraseModel.default(tracks: [monoTrack], layers: layers)
        let monoClip = ClipPoolEntry(
            id: UUID(),
            name: "Mono Source",
            trackType: .monoMelodic,
            content: .stepSequence(stepPattern: [true, false], pitches: [60])
        )
        let polyClip = ClipPoolEntry(
            id: UUID(),
            name: "Chord Source",
            trackType: .polyMelodic,
            content: .pianoRoll(
                lengthBars: 1,
                stepsPerBar: 16,
                notes: [
                    ClipNote(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 100),
                    ClipNote(pitch: 64, startStep: 0, lengthSteps: 4, velocity: 100),
                    ClipNote(pitch: 67, startStep: 0, lengthSteps: 4, velocity: 100),
                ]
            )
        )
        let drumClip = ClipPoolEntry(
            id: UUID(),
            name: "Drum Source",
            trackType: .monoMelodic,
            content: .emptyNoteGrid(lengthSteps: 4)
        )

        let project = Project(
            version: 1,
            tracks: [monoTrack],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [monoClip, polyClip, drumClip],
            layers: layers,
            routes: [],
            patternBanks: [TrackPatternBank.default(for: monoTrack, initialClipID: nil)],
            selectedTrackID: monoTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        XCTAssertEqual(project.compatibleClips(for: monoTrack).map(\.id), [monoClip.id, drumClip.id])
        XCTAssertEqual(Set(project.harmonicSidechainClips().map(\.id)), Set([monoClip.id, polyClip.id]))
    }

    func test_catalog_hides_legacy_progression_and_offers_chord_generator_only_to_chord_tracks() {
        let polyTrack = StepSequenceTrack(
            id: UUID(),
            name: "Poly",
            trackType: .polyMelodic,
            pitches: [60, 64, 67],
            stepPattern: Array(repeating: true, count: 16),
            destination: nil,
            velocity: 100,
            gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [polyTrack])
        let phrase = PhraseModel.default(tracks: [polyTrack], layers: layers)
        let project = Project(
            version: 1,
            tracks: [polyTrack],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [TrackPatternBank.default(for: polyTrack, initialClipID: nil)],
            selectedTrackID: polyTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        XCTAssertFalse(project.compatibleGenerators(for: polyTrack).contains { $0.kind == GeneratorKind.progressionChordGenerator })
        XCTAssertFalse(project.compatibleModifierGenerators(for: polyTrack).contains { $0.kind == GeneratorKind.progressionChordGenerator })
        XCTAssertTrue(project.compatibleModifierGenerators(for: polyTrack).allSatisfy { $0.kind.supportsModifierStage })

        let chordTrack = StepSequenceTrack(
            name: "Chord",
            trackType: .chord,
            pitches: [60, 64, 67],
            stepPattern: Array(repeating: true, count: 16),
            velocity: 100,
            gateLength: 4
        )
        XCTAssertEqual(
            project.compatibleGenerators(for: chordTrack).map(\.kind),
            [.chordGenerator]
        )
        XCTAssertTrue(project.compatibleGenerators(for: polyTrack).allSatisfy { $0.kind != .chordGenerator })
    }

    func test_createBlankGeneratorSource_seeds_chord_palette_slotIDs() throws {
        let first = ChordPaletteSlot(name: "Dm", root: 62, chordID: .minorTriad)
        let second = ChordPaletteSlot(name: "G7", root: 67, chordID: .dominant7th)
        let track = StepSequenceTrack(
            name: "Chord",
            trackType: .chord,
            pitches: [60, 64, 67],
            stepPattern: Array(repeating: true, count: 16),
            velocity: 100,
            gateLength: 4,
            chordPalette: ChordPalette(slots: [first, second])
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [], clipPool: [])
        var project = Project(
            version: 1,
            tracks: [track],
            generatorPool: [],
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [TrackPatternBank.default(for: track, initialClipID: nil)],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        let created = try XCTUnwrap(project.createBlankGeneratorSource(trackID: track.id, slotIndex: 0))
        XCTAssertEqual(created.kind, .chordGenerator)
        XCTAssertEqual(created.trackType, .chord)
        guard case let .chordGenerator(params) = created.params else {
            return XCTFail("expected chord generator params")
        }
        XCTAssertEqual(params.enabledSlotIDs, [first.id, second.id])
    }
}
