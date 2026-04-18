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

    func test_apply_document_model_updates_note_generator_params() {
        let controller = EngineController(client: nil, endpoint: nil)
        let document = SeqAIDocumentModel(
            version: 1,
            primaryTrack: StepSequenceTrack(
                name: "Lead",
                pitches: [72],
                stepPattern: [false, true],
                velocity: 111,
                gateLength: 2
            )
        )

        controller.apply(documentModel: document)

        let firstTick = controller.executor?.tick(now: 0)
        let secondTick = controller.executor?.tick(now: 0.1)

        guard case let .notes(firstNotes)? = firstTick?["gen"]?["notes"] else {
            return XCTFail("expected notes stream on first tick")
        }
        guard case let .notes(secondNotes)? = secondTick?["gen"]?["notes"] else {
            return XCTFail("expected notes stream on second tick")
        }

        XCTAssertTrue(firstNotes.isEmpty)
        XCTAssertEqual(secondNotes.count, 1)
        XCTAssertEqual(secondNotes.first?.pitch, 72)
        XCTAssertEqual(secondNotes.first?.velocity, 111)
        XCTAssertEqual(secondNotes.first?.length, 2)
    }
}
