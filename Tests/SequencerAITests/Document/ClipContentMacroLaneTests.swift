import XCTest
@testable import SequencerAI

final class ClipContentMacroLaneTests: XCTestCase {

    // MARK: - MacroLane basics

    func test_macroLane_initWithStepCount() {
        let lane = MacroLane(stepCount: 4)
        XCTAssertEqual(lane.values.count, 4)
        XCTAssertTrue(lane.values.allSatisfy { $0 == nil })
    }

    func test_macroLane_synced_pads() {
        let lane = MacroLane(values: [0.5, nil])
        let synced = lane.synced(stepCount: 4)
        XCTAssertEqual(synced.values.count, 4)
        XCTAssertEqual(synced.values[0], 0.5)
        XCTAssertNil(synced.values[1])
        XCTAssertNil(synced.values[2])
        XCTAssertNil(synced.values[3])
    }

    func test_macroLane_synced_truncates() {
        let lane = MacroLane(values: [0.1, 0.2, 0.3, 0.4, 0.5])
        let synced = lane.synced(stepCount: 3)
        XCTAssertEqual(synced.values.count, 3)
        XCTAssertEqual(synced.values[2], 0.3)
    }

    func test_macroLane_synced_noChange_whenAlreadyMatching() {
        let lane = MacroLane(values: [0.1, 0.2, 0.3])
        let synced = lane.synced(stepCount: 3)
        XCTAssertEqual(synced.values.count, 3)
    }

    // MARK: - ClipPoolEntry macroLanes round-trip

    func test_clipPoolEntry_roundTrip_withMacroLanes() throws {
        let id1 = UUID()
        let id2 = UUID()
        var entry = ClipPoolEntry(
            id: UUID(),
            name: "Test",
            trackType: .monoMelodic,
            content: .stepSequence(stepPattern: [true, false], pitches: [60])
        )
        entry.macroLanes[id1] = MacroLane(values: [0.5, nil, 1.0])
        entry.macroLanes[id2] = MacroLane(values: [nil, 0.75])

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ClipPoolEntry.self, from: data)
        XCTAssertEqual(decoded.macroLanes[id1]?.values.count, 3)
        XCTAssertEqual(decoded.macroLanes[id1]?.values[0], 0.5)
        XCTAssertNil(decoded.macroLanes[id1]?.values[1])
        XCTAssertEqual(decoded.macroLanes[id2]?.values[1], 0.75)
    }

    func test_clipPoolEntry_legacy_decodesWithEmptyMacroLanes() throws {
        // Simulate old JSON without macroLanes key.
        let legacyJSON = """
        {
          "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "name": "Old Clip",
          "trackType": "monoMelodic",
          "content": {"stepSequence": {"stepPattern": [true], "pitches": [60]}}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ClipPoolEntry.self, from: legacyJSON)
        XCTAssertTrue(decoded.macroLanes.isEmpty)
    }

    // MARK: - synced(with:stepCount:)

    func test_synced_dropsMissingBindingLanes() {
        let keepID = UUID()
        let dropID = UUID()
        var entry = ClipPoolEntry(
            id: UUID(), name: "T", trackType: .monoMelodic,
            content: .stepSequence(stepPattern: [true], pitches: [60])
        )
        entry.macroLanes[keepID] = MacroLane(values: [0.5])
        entry.macroLanes[dropID] = MacroLane(values: [0.3])

        let keepDescriptor = TrackMacroDescriptor(
            id: keepID, displayName: "Keep",
            minValue: 0, maxValue: 1, defaultValue: 0,
            valueType: .scalar, source: .auParameter(address: 1, identifier: "k")
        )
        let bindings = [TrackMacroBinding(descriptor: keepDescriptor)]
        let synced = entry.synced(with: bindings, stepCount: 4)

        XCTAssertNotNil(synced.macroLanes[keepID])
        XCTAssertNil(synced.macroLanes[dropID])
    }

    func test_synced_resizesLanesToStepCount() {
        let macroID = UUID()
        var entry = ClipPoolEntry(
            id: UUID(), name: "T", trackType: .monoMelodic,
            content: .stepSequence(stepPattern: [true, false, true, false], pitches: [60])
        )
        entry.macroLanes[macroID] = MacroLane(values: [0.1, 0.2])

        let descriptor = TrackMacroDescriptor(
            id: macroID, displayName: "X",
            minValue: 0, maxValue: 1, defaultValue: 0,
            valueType: .scalar, source: .auParameter(address: 1, identifier: "x")
        )
        let synced = entry.synced(with: [TrackMacroBinding(descriptor: descriptor)], stepCount: 4)
        XCTAssertEqual(synced.macroLanes[macroID]?.values.count, 4)
    }
}
