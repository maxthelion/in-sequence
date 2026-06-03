import CoreAudio
import XCTest
@testable import SequencerAI

final class MainAudioGraphDeviceSwitchTests: XCTestCase {
    @MainActor
    func test_applyDefaultDevicesToMainAudioGraphSmoke() throws {
        let catalog = CoreAudioDeviceCatalog()
        let inputUID = catalog.defaultDeviceUID(direction: .input)
        let outputUID = catalog.defaultDeviceUID(direction: .output)
        guard inputUID != nil || outputUID != nil else {
            throw XCTSkip("No default CoreAudio input or output device is available.")
        }
        let graph = MainAudioGraph()

        let result = try graph.applyAudioDeviceUIDs(
            inputUID: inputUID,
            outputUID: outputUID
        )

        XCTAssertEqual(result.appliedInputDeviceUID, inputUID)
        XCTAssertEqual(result.appliedOutputDeviceUID, outputUID)
    }

    @MainActor
    func test_invalidCoreAudioUIDLeavesActiveDefaultsUnchanged() throws {
        let catalog = CoreAudioDeviceCatalog()
        let inputUID = catalog.defaultDeviceUID(direction: .input)
        let outputUID = catalog.defaultDeviceUID(direction: .output)
        guard inputUID != nil || outputUID != nil else {
            throw XCTSkip("No default CoreAudio input or output device is available.")
        }
        let graph = MainAudioGraph()

        XCTAssertThrowsError(
            try graph.applyAudioDeviceUIDs(
                inputUID: "missing-input-\(UUID().uuidString)",
                outputUID: outputUID
            )
        )

        XCTAssertEqual(catalog.defaultDeviceUID(direction: .input), inputUID)
        XCTAssertEqual(catalog.defaultDeviceUID(direction: .output), outputUID)
    }

    @MainActor
    func test_runningGraphRestartsAfterVerifiedDeviceOwnerApply() throws {
        let graph = MainAudioGraph()
        do {
            try graph.start()
        } catch {
            throw XCTSkip("CoreAudio engine start is unavailable in this test host: \(error)")
        }
        let owner = FakeAudioDeviceOwner(activeInputUID: "input-a", activeOutputUID: "output-a")

        let result = try graph.applyAudioDeviceUIDs(
            inputUID: "input-b",
            outputUID: "output-b",
            deviceOwner: owner
        )

        XCTAssertEqual(result.appliedInputDeviceUID, "input-b")
        XCTAssertEqual(result.appliedOutputDeviceUID, "output-b")
        XCTAssertTrue(result.wasRunningBeforeApply)
        XCTAssertTrue(result.restartedEngine)
        XCTAssertTrue(graph.engine.isRunning)
    }

    @MainActor
    func test_failedDeviceOwnerSwitchAttemptsRollback() throws {
        let graph = MainAudioGraph()
        let owner = FakeAudioDeviceOwner(
            activeInputUID: "input-a",
            activeOutputUID: "output-a",
            failureUIDs: ["bad-input"]
        )

        XCTAssertThrowsError(
            try graph.applyAudioDeviceUIDs(inputUID: "bad-input", outputUID: "output-b", deviceOwner: owner)
        ) { error in
            guard case let AudioDeviceApplyError.rollbackPerformed(underlying, rollbackError) = error else {
                return XCTFail("Expected rollbackPerformed, got \(error)")
            }
            XCTAssertNil(rollbackError)
            XCTAssertNotNil(underlying)
        }
        XCTAssertEqual(owner.activeDeviceUID(direction: .input), "input-a")
        XCTAssertEqual(owner.activeDeviceUID(direction: .output), "output-a")
    }
}

private final class FakeAudioDeviceOwner: AudioDeviceOwning {
    private var activeInputUID: String?
    private var activeOutputUID: String?
    private let failureUIDs: Set<String>

    init(activeInputUID: String?, activeOutputUID: String?, failureUIDs: Set<String> = []) {
        self.activeInputUID = activeInputUID
        self.activeOutputUID = activeOutputUID
        self.failureUIDs = failureUIDs
    }

    func activeDeviceUID(direction: AudioDeviceDirection) -> String? {
        switch direction {
        case .input: activeInputUID
        case .output: activeOutputUID
        }
    }

    func apply(inputUID: String?, outputUID: String?) throws -> AudioDeviceOwnerApplyResult {
        if inputUID.map(failureUIDs.contains) == true || outputUID.map(failureUIDs.contains) == true {
            throw AudioDeviceApplyError.deviceVerificationFailed(
                direction: inputUID.map(failureUIDs.contains) == true ? .input : .output,
                expectedUID: inputUID.map(failureUIDs.contains) == true ? inputUID : outputUID,
                actualUID: nil
            )
        }
        activeInputUID = inputUID
        activeOutputUID = outputUID
        return AudioDeviceOwnerApplyResult(
            appliedInputDeviceUID: activeInputUID,
            appliedOutputDeviceUID: activeOutputUID
        )
    }
}
