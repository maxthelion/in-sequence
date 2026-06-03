import XCTest
@testable import SequencerAI

final class AudioDeviceSwitchCoordinatorTests: XCTestCase {
    @MainActor
    func test_successfulApplyPersistsAppliedUIDsOnlyAfterEngineApply() throws {
        let store = AudioDevicePreferenceStore(preferenceURL: temporaryPreferenceURL())
        let catalog = FakeAudioDeviceCatalog()
        var applied: [(String?, String?)] = []
        let coordinator = AudioDeviceSwitchCoordinator(catalog: catalog, store: store) { inputUID, outputUID in
            applied.append((inputUID, outputUID))
            return AudioDeviceApplyResult(
                appliedInputDeviceUID: inputUID,
                appliedOutputDeviceUID: outputUID,
                wasRunningBeforeApply: true,
                restartedEngine: true
            )
        }

        let result = try coordinator.apply(inputUID: "input-a", outputUID: "output-a")

        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(result.appliedInputDeviceUID, "input-a")
        XCTAssertEqual(result.appliedOutputDeviceUID, "output-a")
        XCTAssertEqual(
            store.load(),
            AudioDevicePreference(preferredInputDeviceUID: "input-a", preferredOutputDeviceUID: "output-a")
        )
    }

    @MainActor
    func test_failedApplyDoesNotPersistFailedUID() throws {
        let store = AudioDevicePreferenceStore(preferenceURL: temporaryPreferenceURL())
        try store.save(AudioDevicePreference(preferredInputDeviceUID: "input-a", preferredOutputDeviceUID: "output-a"))
        let coordinator = AudioDeviceSwitchCoordinator(catalog: FakeAudioDeviceCatalog(), store: store) { _, _ in
            throw AudioDeviceApplyError.missingAudioUnit(.input)
        }

        XCTAssertThrowsError(try coordinator.apply(inputUID: "bad-input", outputUID: "output-a"))
        XCTAssertEqual(
            store.load(),
            AudioDevicePreference(preferredInputDeviceUID: "input-a", preferredOutputDeviceUID: "output-a")
        )
    }

    func test_missingPreferredDeviceFallsBackToDefaultWithoutOverwritingPreference() throws {
        let store = AudioDevicePreferenceStore(preferenceURL: temporaryPreferenceURL())
        try store.save(AudioDevicePreference(preferredInputDeviceUID: "missing-input", preferredOutputDeviceUID: "missing-output"))
        let coordinator = AudioDeviceSwitchCoordinator(catalog: FakeAudioDeviceCatalog(), store: store) { _, _ in
            XCTFail("Startup fallback should not apply or persist until the user applies a device.")
            return AudioDeviceApplyResult(
                appliedInputDeviceUID: nil,
                appliedOutputDeviceUID: nil,
                wasRunningBeforeApply: false,
                restartedEngine: false
            )
        }

        let resolution = coordinator.loadStartupPreference()

        XCTAssertEqual(resolution.resolvedInputDeviceUID, "input-a")
        XCTAssertEqual(resolution.resolvedOutputDeviceUID, "output-a")
        XCTAssertEqual(resolution.missingInputDeviceUID, "missing-input")
        XCTAssertEqual(resolution.missingOutputDeviceUID, "missing-output")
        XCTAssertEqual(
            store.load(),
            AudioDevicePreference(preferredInputDeviceUID: "missing-input", preferredOutputDeviceUID: "missing-output")
        )
    }

    private func temporaryPreferenceURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return directory.appendingPathComponent("audio-device.json")
    }
}

private final class FakeAudioDeviceCatalog: AudioDeviceCataloging {
    private let inputs = [
        AudioDeviceDescriptor(uid: "input-a", displayName: "Input A", direction: .input, channelCount: 2),
        AudioDeviceDescriptor(uid: "input-b", displayName: "Input B", direction: .input, channelCount: 1),
    ]
    private let outputs = [
        AudioDeviceDescriptor(uid: "output-a", displayName: "Output A", direction: .output, channelCount: 2),
        AudioDeviceDescriptor(uid: "output-b", displayName: "Output B", direction: .output, channelCount: 2),
    ]

    func devices(direction: AudioDeviceDirection) -> [AudioDeviceDescriptor] {
        switch direction {
        case .input: inputs
        case .output: outputs
        }
    }

    func device(uid: String, direction: AudioDeviceDirection) -> AudioDeviceDescriptor? {
        devices(direction: direction).first { $0.uid == uid }
    }

    func defaultDeviceUID(direction: AudioDeviceDirection) -> String? {
        switch direction {
        case .input: "input-a"
        case .output: "output-a"
        }
    }
}
