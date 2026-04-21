import Foundation
import XCTest
@testable import SequencerAI

final class TrackPatternBankSyncedTests: XCTestCase {
    private func monoGenerator(id: UUID) -> GeneratorPoolEntry {
        GeneratorPoolEntry(
            id: id,
            name: "Gen",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .defaultMono
        )
    }

    func test_synced_preserves_attachedGeneratorID_when_present_in_pool() {
        let track = StepSequenceTrack.default
        let generatorID = UUID()
        let bank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(nil))],
            attachedGeneratorID: generatorID
        )

        let synced = bank.synced(
            track: track,
            generatorPool: [monoGenerator(id: generatorID)],
            clipPool: []
        )

        XCTAssertEqual(synced.attachedGeneratorID, generatorID)
    }

    func test_synced_clears_attachedGeneratorID_when_missing_from_pool() {
        let track = StepSequenceTrack.default
        let missingID = UUID()
        let bank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(nil))],
            attachedGeneratorID: missingID
        )

        let synced = bank.synced(
            track: track,
            generatorPool: [],
            clipPool: []
        )

        XCTAssertNil(synced.attachedGeneratorID, "dangling attachedGeneratorID should be dropped when the entry is gone")
    }

    func test_synced_clears_attachedGeneratorID_on_trackType_mismatch() {
        let track = StepSequenceTrack.default // monoMelodic
        let generatorID = UUID()
        let polyGenerator = GeneratorPoolEntry(
            id: generatorID,
            name: "Poly",
            trackType: .polyMelodic,
            kind: .polyGenerator,
            params: .poly(step: .manual(pattern: Array(repeating: false, count: 16)), pitches: [.manual(pitches: [60], pickMode: .random)], shape: .default)
        )
        let bank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(nil))],
            attachedGeneratorID: generatorID
        )

        let synced = bank.synced(
            track: track,
            generatorPool: [polyGenerator],
            clipPool: []
        )

        XCTAssertNil(synced.attachedGeneratorID, "attachedGeneratorID pointing at an incompatible-trackType entry should be dropped")
    }
}
