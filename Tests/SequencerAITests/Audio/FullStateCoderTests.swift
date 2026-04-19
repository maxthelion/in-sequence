import Foundation
import XCTest
@testable import SequencerAI

final class FullStateCoderTests: XCTestCase {
    func test_encode_nil_returns_nil() throws {
        XCTAssertNil(try FullStateCoder.encode(nil))
    }

    func test_roundtrip_dictionary_payload() throws {
        let payload: [String: Any] = [
            "foo": "bar",
            "count": 7,
            "blob": Data(repeating: 0xFE, count: 16),
        ]

        let encoded = try XCTUnwrap(FullStateCoder.encode(payload))
        let decoded = try XCTUnwrap(FullStateCoder.decode(encoded))

        XCTAssertEqual(decoded["foo"] as? String, "bar")
        XCTAssertEqual(decoded["count"] as? Int, 7)
        XCTAssertEqual(decoded["blob"] as? Data, Data(repeating: 0xFE, count: 16))
    }

    func test_decode_garbage_throws_unarchive_failed() {
        XCTAssertThrowsError(try FullStateCoder.decode(Data("not-an-archive".utf8))) { error in
            XCTAssertEqual(error as? FullStateCoder.CoderError, .unarchiveFailed)
        }
    }
}
