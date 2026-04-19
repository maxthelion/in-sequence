import Foundation
import XCTest
@testable import SequencerAI

final class RecentVoicesStoreTests: XCTestCase {
    func test_load_on_missing_file_returns_empty() {
        let store = RecentVoicesStore(historyURL: temporaryHistoryURL())
        XCTAssertEqual(store.load(), [])
    }

    func test_record_and_load_roundtrip() {
        let store = RecentVoicesStore(historyURL: temporaryHistoryURL())
        let voice = RecentVoice(
            name: "Lead",
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: Data([0x01]))
        )

        store.record(voice)

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Lead")
        XCTAssertEqual(loaded[0].destination, voice.destination)
    }

    func test_prune_keeps_newest_entries() {
        let store = RecentVoicesStore(historyURL: temporaryHistoryURL())
        let older = RecentVoice(
            id: UUID(),
            name: "Old",
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            firstSeen: Date(timeIntervalSince1970: 1),
            lastUsed: Date(timeIntervalSince1970: 1)
        )
        let newer = RecentVoice(
            id: UUID(),
            name: "New",
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            firstSeen: Date(timeIntervalSince1970: 2),
            lastUsed: Date(timeIntervalSince1970: 2)
        )

        store.record(older)
        store.record(newer)
        store.prune(maxEntries: 1)

        XCTAssertEqual(store.load().map(\.name), ["New"])
    }

    private func temporaryHistoryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return directory.appendingPathComponent("history.json")
    }
}
