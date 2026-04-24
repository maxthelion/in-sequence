import XCTest
@testable import SequencerAI

final class SnapshotChangeTypeTests: XCTestCase {

    func test_selectedTrackOnly_isPlaybackInert() {
        XCTAssertFalse(SnapshotChange.selectedTrack.requiresPlaybackSnapshotInstall)
    }

    func test_unionOfRepeatedNarrowChanges_deduplicatesByID() {
        let id = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let merged = SnapshotChange.clip(id).union(.clip(id)).union(.phrase(id))

        XCTAssertEqual(merged.clipIDs, [id])
        XCTAssertEqual(merged.phraseIDs, [id])
        XCTAssertFalse(merged.fullRebuild)
    }

    func test_fullRebuildDominatesNarrowChanges() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let merged = SnapshotChange.full.union(.clip(id))

        XCTAssertTrue(merged.fullRebuild)
        XCTAssertTrue(merged.requiresPlaybackSnapshotInstall)
    }
}
