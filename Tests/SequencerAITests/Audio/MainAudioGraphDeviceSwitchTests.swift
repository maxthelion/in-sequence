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

        // Lazy input arming: with no armed audio-input routing the input
        // selection is recorded, not applied (creating the input AUHAL is a
        // mic-TCC trigger).
        XCTAssertNil(result.appliedInputDeviceUID)
        XCTAssertEqual(result.deferredInputDeviceUID, inputUID)
        XCTAssertEqual(result.appliedOutputDeviceUID, outputUID)
    }

    @MainActor
    func test_invalidOutputCoreAudioUIDLeavesActiveDefaultsUnchanged() throws {
        let catalog = CoreAudioDeviceCatalog()
        let inputUID = catalog.defaultDeviceUID(direction: .input)
        let outputUID = catalog.defaultDeviceUID(direction: .output)
        guard inputUID != nil || outputUID != nil else {
            throw XCTSkip("No default CoreAudio input or output device is available.")
        }
        let graph = MainAudioGraph()

        XCTAssertThrowsError(
            try graph.applyAudioDeviceUIDs(
                inputUID: inputUID,
                outputUID: "missing-output-\(UUID().uuidString)"
            )
        )

        XCTAssertEqual(catalog.defaultDeviceUID(direction: .input), inputUID)
        XCTAssertEqual(catalog.defaultDeviceUID(direction: .output), outputUID)
    }

    @MainActor
    func test_invalidInputCoreAudioUIDIsDeferredNotValidatedWhileUnarmed() throws {
        let catalog = CoreAudioDeviceCatalog()
        guard catalog.defaultDeviceUID(direction: .output) != nil else {
            throw XCTSkip("No default CoreAudio output device is available.")
        }
        let graph = MainAudioGraph()
        let bogusInputUID = "missing-input-\(UUID().uuidString)"

        // With no armed audio-input routing the input UID never reaches the
        // HAL owner, so it cannot fail: it is recorded as deferred. (It gets
        // validated when the input side actually arms and applies.)
        let result = try graph.applyAudioDeviceUIDs(
            inputUID: bogusInputUID,
            outputUID: catalog.defaultDeviceUID(direction: .output)
        )

        XCTAssertNil(result.appliedInputDeviceUID)
        XCTAssertEqual(result.deferredInputDeviceUID, bogusInputUID)
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

        // Input deferred (no armed audio-input routing); output applied live.
        XCTAssertNil(result.appliedInputDeviceUID)
        XCTAssertEqual(result.deferredInputDeviceUID, "input-b")
        XCTAssertEqual(owner.activeDeviceUID(direction: .input), "input-a")
        XCTAssertEqual(result.appliedOutputDeviceUID, "output-b")
        XCTAssertTrue(result.wasRunningBeforeApply)
        XCTAssertTrue(result.restartedEngine)
        XCTAssertTrue(graph.engine.isRunning)
    }

    @MainActor
    func test_armedInputRoutingAppliesInputDeviceThroughOwner() throws {
        MainAudioGraph.simulateAudioInputConnectionForTesting = true
        defer { MainAudioGraph.simulateAudioInputConnectionForTesting = false }

        let graph = MainAudioGraph()
        graph.syncAudioInputRoutings([
            MainAudioGraph.AudioInputRoutingRequest(
                trackID: UUID(),
                source: .input,
                selectedChannel: .stereo(firstChannel: 0),
                outputBusID: nil,
                mix: .default
            ),
        ])
        let owner = FakeAudioDeviceOwner(activeInputUID: "input-a", activeOutputUID: "output-a")

        let result = try graph.applyAudioDeviceUIDs(
            inputUID: "input-b",
            outputUID: "output-b",
            deviceOwner: owner
        )

        XCTAssertEqual(result.appliedInputDeviceUID, "input-b")
        XCTAssertNil(result.deferredInputDeviceUID)
        XCTAssertEqual(owner.activeDeviceUID(direction: .input), "input-b")
        XCTAssertEqual(result.appliedOutputDeviceUID, "output-b")
    }

    @MainActor
    func test_failedDeviceOwnerSwitchAttemptsRollback() throws {
        let graph = MainAudioGraph()
        let owner = FakeAudioDeviceOwner(
            activeInputUID: "input-a",
            activeOutputUID: "output-a",
            failureUIDs: ["bad-output"]
        )

        XCTAssertThrowsError(
            try graph.applyAudioDeviceUIDs(inputUID: "input-b", outputUID: "bad-output", deviceOwner: owner)
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
        // Mirrors CoreAudioHALDeviceOwner: a nil UID leaves that direction
        // untouched (no unit created / no re-point).
        if let inputUID { activeInputUID = inputUID }
        if let outputUID { activeOutputUID = outputUID }
        return AudioDeviceOwnerApplyResult(
            appliedInputDeviceUID: inputUID != nil ? activeInputUID : nil,
            appliedOutputDeviceUID: outputUID != nil ? activeOutputUID : nil
        )
    }
}
