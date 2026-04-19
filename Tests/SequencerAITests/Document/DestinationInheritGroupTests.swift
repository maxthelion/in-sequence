import Foundation
import XCTest
@testable import SequencerAI

final class DestinationInheritGroupTests: XCTestCase {
    func test_inherit_group_round_trips_through_codable() throws {
        let data = try JSONEncoder().encode(Destination.inheritGroup)
        let decoded = try JSONDecoder().decode(Destination.self, from: data)

        XCTAssertEqual(decoded, .inheritGroup)
    }

    func test_inherit_group_kind_label_is_group() {
        XCTAssertEqual(Destination.inheritGroup.kindLabel, "Group")
    }
}
