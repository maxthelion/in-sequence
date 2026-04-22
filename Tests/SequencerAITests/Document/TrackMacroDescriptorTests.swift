import XCTest
@testable import SequencerAI

final class TrackMacroDescriptorTests: XCTestCase {

    // MARK: - JSON Round-trip

    func test_roundTrip_builtinDescriptor() throws {
        let trackID = UUID()
        let descriptor = TrackMacroDescriptor.builtin(trackID: trackID, kind: .sampleGain)
        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(TrackMacroDescriptor.self, from: data)
        XCTAssertEqual(decoded, descriptor)
        XCTAssertEqual(decoded.source, .builtin(.sampleGain))
    }

    func test_roundTrip_auParameterDescriptor() throws {
        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Cutoff",
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 12345, identifier: "cutoff.main")
        )
        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(TrackMacroDescriptor.self, from: data)
        XCTAssertEqual(decoded, descriptor)
        XCTAssertEqual(decoded.source, .auParameter(address: 12345, identifier: "cutoff.main"))
    }

    // MARK: - Equality

    func test_sameID_areEqual() {
        let trackID = UUID()
        let d1 = TrackMacroDescriptor.builtin(trackID: trackID, kind: .sampleStart)
        let d2 = TrackMacroDescriptor.builtin(trackID: trackID, kind: .sampleStart)
        XCTAssertEqual(d1, d2)
    }

    func test_differentDisplayName_notEqual() {
        let trackID = UUID()
        let d1 = TrackMacroDescriptor.builtin(trackID: trackID, kind: .sampleStart)
        var d2 = d1
        d2.displayName = "Renamed"
        XCTAssertNotEqual(d1, d2)
    }

    // MARK: - Stable Built-in IDs

    func test_builtinID_isStable() {
        let trackID = UUID()
        let id1 = TrackMacroDescriptor.builtinID(trackID: trackID, kind: .sampleGain)
        let id2 = TrackMacroDescriptor.builtinID(trackID: trackID, kind: .sampleGain)
        XCTAssertEqual(id1, id2)
    }

    func test_builtinID_differsByKind() {
        let trackID = UUID()
        let startID = TrackMacroDescriptor.builtinID(trackID: trackID, kind: .sampleStart)
        let gainID = TrackMacroDescriptor.builtinID(trackID: trackID, kind: .sampleGain)
        XCTAssertNotEqual(startID, gainID)
    }

    func test_builtinID_differsByTrack() {
        let id1 = TrackMacroDescriptor.builtinID(trackID: UUID(), kind: .sampleStart)
        let id2 = TrackMacroDescriptor.builtinID(trackID: UUID(), kind: .sampleStart)
        XCTAssertNotEqual(id1, id2)
    }

    // MARK: - BuiltinMacroKind

    func test_builtinMacroKind_allCasesRoundTrip() throws {
        for kind in BuiltinMacroKind.allCases {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(BuiltinMacroKind.self, from: data)
            XCTAssertEqual(decoded, kind)
        }
    }

    func test_builtinMacroKind_hasExpectedCases() {
        // 3 sampler cases + 5 filter cases = 8 total
        XCTAssertEqual(BuiltinMacroKind.allCases.count, 8)
        XCTAssertTrue(BuiltinMacroKind.allCases.contains(.sampleStart))
        XCTAssertTrue(BuiltinMacroKind.allCases.contains(.sampleLength))
        XCTAssertTrue(BuiltinMacroKind.allCases.contains(.sampleGain))
        XCTAssertTrue(BuiltinMacroKind.allCases.contains(.samplerFilterCutoff))
        XCTAssertTrue(BuiltinMacroKind.allCases.contains(.samplerFilterReso))
        XCTAssertTrue(BuiltinMacroKind.allCases.contains(.samplerFilterDrive))
        XCTAssertTrue(BuiltinMacroKind.allCases.contains(.samplerFilterType))
        XCTAssertTrue(BuiltinMacroKind.allCases.contains(.samplerFilterPoles))
    }

    // MARK: - TrackMacroBinding round-trip

    func test_binding_roundTrip() throws {
        let trackID = UUID()
        let binding = TrackMacroBinding(
            descriptor: TrackMacroDescriptor.builtin(trackID: trackID, kind: .sampleLength)
        )
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(TrackMacroBinding.self, from: data)
        XCTAssertEqual(decoded, binding)
    }
}
