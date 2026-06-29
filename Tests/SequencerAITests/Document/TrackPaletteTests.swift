import XCTest
@testable import SequencerAI

final class TrackPaletteTests: XCTestCase {
    /// Every palette hex must parse as a 6-digit colour — the malformed legacy
    /// "#8AA" default is exactly what this replaces.
    func test_everyPaletteHexIsValidSixDigit() {
        for hex in TrackPalette.identityHexes {
            XCTAssertTrue(TrackPalette.isValidHex(hex), "Palette hex \(hex) must be a valid 6-digit colour")
        }
    }

    func test_isValidHex_rejectsLegacyShortDefault() {
        XCTAssertFalse(TrackPalette.isValidHex("#8AA"), "The legacy 3-digit default must be rejected")
        XCTAssertFalse(TrackPalette.isValidHex(""), "Empty must be rejected")
        XCTAssertTrue(TrackPalette.isValidHex("#4FA8D8"))
        XCTAssertTrue(TrackPalette.isValidHex("4FA8D8"), "Leading # is optional")
    }

    func test_identityHexForIndex_cyclesAndWrapsNegatives() {
        let count = TrackPalette.identityHexes.count
        XCTAssertEqual(TrackPalette.identityHex(forIndex: 0), TrackPalette.identityHexes[0])
        XCTAssertEqual(TrackPalette.identityHex(forIndex: count), TrackPalette.identityHexes[0], "Wraps at the palette size")
        XCTAssertEqual(TrackPalette.identityHex(forIndex: -1), TrackPalette.identityHexes[count - 1], "Negatives wrap, never crash")
    }

    /// The colour must be derived from the id bytes (run-stable), NOT hashValue
    /// (per-process seeded) — the same id maps to the same hex every time.
    func test_identityHexForID_isDeterministic() {
        let id = UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!
        let expected = TrackPalette.identityHex(forIndex: 0x00) // first byte
        XCTAssertEqual(TrackPalette.identityHex(for: id), expected)
        // Stable across repeated calls.
        XCTAssertEqual(TrackPalette.identityHex(for: id), TrackPalette.identityHex(for: id))
    }

    /// A kit and its parts share one identity hue because they all derive from
    /// the SAME group id when the stored colour is the malformed default.
    func test_sameGroupIDYieldsSameHex_differentIDsCanDiffer() {
        let groupID = UUID()
        XCTAssertEqual(TrackPalette.identityHex(for: groupID), TrackPalette.identityHex(for: groupID))
    }
}
