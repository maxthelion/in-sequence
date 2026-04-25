import XCTest
@testable import SequencerAI

final class PresetStepperTests: XCTestCase {
    func test_descriptors_preserves_factory_then_user_order() {
        let readout = PresetReadout(
            factory: [.factory(number: 1, name: "Init"), .factory(number: 2, name: "Bass")],
            user: [.user(number: -1, name: "Pad")],
            currentID: nil
        )

        XCTAssertEqual(
            PresetStepper.descriptors(in: readout).map(\.id),
            ["factory:1", "factory:2", "user:-1:Pad"]
        )
    }

    func test_target_next_wraps_to_first() {
        let readout = PresetReadout(
            factory: [.factory(number: 1, name: "Init"), .factory(number: 2, name: "Bass")],
            user: [],
            currentID: "factory:2"
        )

        XCTAssertEqual(
            PresetStepper.target(from: readout, direction: .next)?.id,
            "factory:1"
        )
    }

    func test_target_previous_wraps_to_last() {
        let readout = PresetReadout(
            factory: [.factory(number: 1, name: "Init"), .factory(number: 2, name: "Bass")],
            user: [],
            currentID: "factory:1"
        )

        XCTAssertEqual(
            PresetStepper.target(from: readout, direction: .previous)?.id,
            "factory:2"
        )
    }

    func test_target_uses_first_or_last_when_no_current_preset() {
        let readout = PresetReadout(
            factory: [.factory(number: 1, name: "Init")],
            user: [.user(number: -1, name: "Pad"), .user(number: -2, name: "Lead")],
            currentID: nil
        )

        XCTAssertEqual(
            PresetStepper.target(from: readout, direction: .next)?.id,
            "factory:1"
        )
        XCTAssertEqual(
            PresetStepper.target(from: readout, direction: .previous)?.id,
            "user:-2:Lead"
        )
    }

    func test_target_returns_nil_when_only_one_preset_exists() {
        let readout = PresetReadout(
            factory: [.factory(number: 1, name: "Init")],
            user: [],
            currentID: "factory:1"
        )

        XCTAssertNil(PresetStepper.target(from: readout, direction: .next))
        XCTAssertNil(PresetStepper.target(from: readout, direction: .previous))
    }

    func test_target_returns_nil_for_empty_preset_list() {
        let readout = PresetReadout(
            factory: [],
            user: [],
            currentID: nil
        )

        XCTAssertNil(PresetStepper.target(from: readout, direction: .next))
        XCTAssertNil(PresetStepper.target(from: readout, direction: .previous))
    }

    func test_target_steps_through_user_presets_after_factory() {
        let readout = PresetReadout(
            factory: [.factory(number: 1, name: "Init")],
            user: [.user(number: -1, name: "Pad")],
            currentID: "factory:1"
        )

        XCTAssertEqual(
            PresetStepper.target(from: readout, direction: .next)?.id,
            "user:-1:Pad"
        )
    }
}
