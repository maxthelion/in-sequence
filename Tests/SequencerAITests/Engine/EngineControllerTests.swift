import XCTest
@testable import SequencerAI

final class EngineControllerTests: XCTestCase {
    func test_init_registers_core_blocks_and_builds_default_pipeline() {
        let controller = EngineController(client: nil, endpoint: nil)

        XCTAssertEqual(Set(controller.registeredKindIDs), ["note-generator", "midi-out"])
        XCTAssertNotNil(controller.executor)
    }

    func test_start_and_stop_toggle_running_state() {
        let controller = EngineController(client: nil, endpoint: nil)

        controller.start()
        XCTAssertTrue(controller.isRunning)

        controller.stop()
        XCTAssertFalse(controller.isRunning)
    }

    func test_setBPM_reaches_executor_within_two_ticks() {
        let controller = EngineController(client: nil, endpoint: nil)

        controller.setBPM(240)
        controller.start()
        controller.setBPM(120)

        let deadline = Date().addingTimeInterval(0.4)
        while controller.executor?.currentBPM != 120 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        controller.stop()
        XCTAssertEqual(controller.executor?.currentBPM, 120)
    }
}
