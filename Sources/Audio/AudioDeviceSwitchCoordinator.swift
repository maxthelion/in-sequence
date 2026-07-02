import AudioToolbox
import CoreAudio
import Foundation

struct AudioDeviceApplyResult: Equatable, Sendable {
    var appliedInputDeviceUID: String?
    var appliedOutputDeviceUID: String?
    var wasRunningBeforeApply: Bool
    var restartedEngine: Bool
    /// Input selection that was RECORDED but not applied to the HAL because no
    /// audio-input routing was armed at apply time (lazy input arming: creating
    /// the input-direction AUHAL is a mic-TCC trigger, so it is deferred until
    /// an input routing actually arms). Preference persistence must treat this
    /// as the user's selection.
    var deferredInputDeviceUID: String? = nil
}

struct AudioDeviceOwnerApplyResult: Equatable, Sendable {
    var appliedInputDeviceUID: String?
    var appliedOutputDeviceUID: String?
    /// Resolved CoreAudio ID for the applied input device, so the audio
    /// graph can point AVAudioEngine's input node at it (the engine's
    /// input otherwise follows the system default device, ignoring the
    /// in-app selection entirely).
    var appliedInputDeviceID: AudioDeviceID?
}

enum AudioDeviceApplyError: Error, LocalizedError {
    case missingAudioUnit(AudioDeviceDirection)
    case deviceVerificationFailed(direction: AudioDeviceDirection, expectedUID: String?, actualUID: String?)
    case rollbackPerformed(underlying: Error, rollbackError: Error?)

    var errorDescription: String? {
        switch self {
        case let .missingAudioUnit(direction):
            "The \(direction.rawValue) audio unit is unavailable."
        case let .deviceVerificationFailed(direction, expectedUID, actualUID):
            "The \(direction.rawValue) audio device did not become active. Expected \(expectedUID ?? "none"), got \(actualUID ?? "none")."
        case let .rollbackPerformed(underlying, rollbackError):
            if let rollbackError {
                "Audio device switch failed and rollback also failed: \(underlying); rollback: \(rollbackError)."
            } else {
                "Audio device switch failed; restored the previous audio device: \(underlying)."
            }
        }
    }
}

protocol AudioDeviceOwning {
    func activeDeviceUID(direction: AudioDeviceDirection) -> String?
    func apply(inputUID: String?, outputUID: String?) throws -> AudioDeviceOwnerApplyResult
}

final class CoreAudioHALDeviceOwner: AudioDeviceOwning {
    private let catalog: AudioHardwareDeviceResolving
    private var inputUnit: HALAudioUnit?
    private var outputUnit: HALAudioUnit?

    init(catalog: AudioHardwareDeviceResolving = CoreAudioDeviceCatalog()) {
        self.catalog = catalog
    }

    func activeDeviceUID(direction: AudioDeviceDirection) -> String? {
        switch direction {
        case .input:
            return inputUnit?.activeDeviceUID(catalog: catalog) ?? catalog.defaultDeviceUID(direction: .input)
        case .output:
            return outputUnit?.activeDeviceUID(catalog: catalog) ?? catalog.defaultDeviceUID(direction: .output)
        }
    }

    func apply(inputUID: String?, outputUID: String?) throws -> AudioDeviceOwnerApplyResult {
        let previousInputDeviceID = currentDeviceID(direction: .input)
        let previousOutputDeviceID = currentDeviceID(direction: .output)

        do {
            let targetInputDeviceID = try targetDeviceID(preferredUID: inputUID, direction: .input)
            let targetOutputDeviceID = try targetDeviceID(preferredUID: outputUID, direction: .output)

            if let targetInputDeviceID {
                try apply(deviceID: targetInputDeviceID, direction: .input)
            }
            if let targetOutputDeviceID {
                try apply(deviceID: targetOutputDeviceID, direction: .output)
            }

            return AudioDeviceOwnerApplyResult(
                appliedInputDeviceUID: try verifiedActiveUID(targetInputDeviceID, direction: .input),
                appliedOutputDeviceUID: try verifiedActiveUID(targetOutputDeviceID, direction: .output),
                appliedInputDeviceID: targetInputDeviceID
            )
        } catch {
            let rollbackError = rollback(
                inputDeviceID: previousInputDeviceID,
                outputDeviceID: previousOutputDeviceID
            )
            throw AudioDeviceApplyError.rollbackPerformed(underlying: error, rollbackError: rollbackError)
        }
    }

    private func currentDeviceID(direction: AudioDeviceDirection) -> AudioDeviceID? {
        switch direction {
        case .input:
            return inputUnit?.currentDeviceID ?? (try? catalog.defaultDeviceID(direction: .input))
        case .output:
            return outputUnit?.currentDeviceID ?? (try? catalog.defaultDeviceID(direction: .output))
        }
    }

    /// True once the input-direction AUHAL exists. Creating that unit is a
    /// mic-TCC trigger; tests pin that sample-only paths never create it.
    var hasCreatedInputUnitForTesting: Bool {
        inputUnit != nil
    }

    private func targetDeviceID(preferredUID: String?, direction: AudioDeviceDirection) throws -> AudioDeviceID? {
        if let preferredUID {
            return try catalog.deviceID(for: preferredUID, direction: direction)
        }
        // Never create (or re-point) the INPUT-direction AUHAL without an
        // explicit selection: it is an input-ENABLED IO unit, and
        // creating/initializing one raises the microphone TCC prompt. With no
        // explicit choice the input follows the system-default device, which
        // needs no unit at all — so a nil input UID leaves the input side
        // completely untouched instead of pinning it to the current default.
        if direction == .input { return nil }
        return try? catalog.defaultDeviceID(direction: direction)
    }

    private func apply(deviceID: AudioDeviceID, direction: AudioDeviceDirection) throws {
        switch direction {
        case .input:
            if inputUnit == nil {
                inputUnit = try HALAudioUnit(direction: .input)
            }
            try inputUnit?.apply(deviceID: deviceID)
        case .output:
            if outputUnit == nil {
                outputUnit = try HALAudioUnit(direction: .output)
            }
            try outputUnit?.apply(deviceID: deviceID)
        }
    }

    private func verifiedActiveUID(_ targetDeviceID: AudioDeviceID?, direction: AudioDeviceDirection) throws -> String? {
        guard let targetDeviceID else { return nil }
        let expectedUID = catalog.deviceUID(for: targetDeviceID)
        let actualUID = activeDeviceUID(direction: direction)
        guard expectedUID == actualUID else {
            throw AudioDeviceApplyError.deviceVerificationFailed(
                direction: direction,
                expectedUID: expectedUID,
                actualUID: actualUID
            )
        }
        return actualUID
    }

    private func rollback(inputDeviceID: AudioDeviceID?, outputDeviceID: AudioDeviceID?) -> Error? {
        do {
            if let inputDeviceID {
                try apply(deviceID: inputDeviceID, direction: .input)
            }
            if let outputDeviceID {
                try apply(deviceID: outputDeviceID, direction: .output)
            }
            return nil
        } catch {
            return error
        }
    }

    private final class HALAudioUnit {
        private let audioUnit: AudioUnit
        private let direction: AudioDeviceDirection
        private var isInitialized = false
        private(set) var currentDeviceID: AudioDeviceID?

        init(direction: AudioDeviceDirection) throws {
            self.direction = direction

            var description = AudioComponentDescription(
                componentType: kAudioUnitType_Output,
                componentSubType: kAudioUnitSubType_HALOutput,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            guard let component = AudioComponentFindNext(nil, &description) else {
                throw AudioDeviceApplyError.missingAudioUnit(direction)
            }

            var createdUnit: AudioUnit?
            let status = AudioComponentInstanceNew(component, &createdUnit)
            try CoreAudioDeviceCatalog.throwIfNeeded(status, operation: "Create \(direction.rawValue) AUHAL unit")
            guard let createdUnit else {
                throw AudioDeviceApplyError.missingAudioUnit(direction)
            }
            self.audioUnit = createdUnit
            try configureIO()
        }

        deinit {
            if isInitialized {
                AudioUnitUninitialize(audioUnit)
            }
            AudioComponentInstanceDispose(audioUnit)
        }

        func activeDeviceUID(catalog: AudioHardwareDeviceResolving) -> String? {
            guard let currentDeviceID else { return nil }
            return catalog.deviceUID(for: currentDeviceID)
        }

        func apply(deviceID: AudioDeviceID) throws {
            if currentDeviceID == deviceID, isInitialized { return }
            if isInitialized {
                try uninitialize()
            }

            var mutableDeviceID = deviceID
            var status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableDeviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            try CoreAudioDeviceCatalog.throwIfNeeded(
                status,
                operation: "Set current \(direction.rawValue) AUHAL device"
            )

            var verifiedDeviceID = AudioDeviceID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            status = AudioUnitGetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &verifiedDeviceID,
                &size
            )
            try CoreAudioDeviceCatalog.throwIfNeeded(
                status,
                operation: "Read current \(direction.rawValue) AUHAL device"
            )
            guard verifiedDeviceID == deviceID else {
                throw AudioDeviceApplyError.deviceVerificationFailed(
                    direction: direction,
                    expectedUID: "\(deviceID)",
                    actualUID: "\(verifiedDeviceID)"
                )
            }

            status = AudioUnitInitialize(audioUnit)
            try CoreAudioDeviceCatalog.throwIfNeeded(status, operation: "Initialize \(direction.rawValue) AUHAL unit")
            currentDeviceID = verifiedDeviceID
            isInitialized = true
        }

        private func configureIO() throws {
            var enableIO: UInt32 = 1
            var disableIO: UInt32 = 0

            switch direction {
            case .input:
                try setEnableIO(&enableIO, scope: kAudioUnitScope_Input, element: 1, operation: "Enable input AUHAL IO")
                try setEnableIO(&disableIO, scope: kAudioUnitScope_Output, element: 0, operation: "Disable input AUHAL output")
            case .output:
                try setEnableIO(&enableIO, scope: kAudioUnitScope_Output, element: 0, operation: "Enable output AUHAL IO")
                try setEnableIO(&disableIO, scope: kAudioUnitScope_Input, element: 1, operation: "Disable output AUHAL input")
            }
        }

        private func setEnableIO(
            _ value: inout UInt32,
            scope: AudioUnitScope,
            element: AudioUnitElement,
            operation: String
        ) throws {
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_EnableIO,
                scope,
                element,
                &value,
                UInt32(MemoryLayout<UInt32>.size)
            )
            try CoreAudioDeviceCatalog.throwIfNeeded(status, operation: operation)
        }

        private func uninitialize() throws {
            let status = AudioUnitUninitialize(audioUnit)
            try CoreAudioDeviceCatalog.throwIfNeeded(status, operation: "Uninitialize \(direction.rawValue) AUHAL unit")
            isInitialized = false
        }
    }
}

struct AudioDeviceStartupResolution: Equatable, Sendable {
    var preference: AudioDevicePreference
    var resolvedInputDeviceUID: String?
    var resolvedOutputDeviceUID: String?
    var missingInputDeviceUID: String?
    var missingOutputDeviceUID: String?
}

final class AudioDeviceSwitchCoordinator {
    typealias ApplyHandler = @MainActor (_ inputUID: String?, _ outputUID: String?) throws -> AudioDeviceApplyResult

    private let catalog: AudioDeviceCataloging
    private let store: AudioDevicePreferenceStore
    private let applyHandler: ApplyHandler

    init(
        catalog: AudioDeviceCataloging = CoreAudioDeviceCatalog(),
        store: AudioDevicePreferenceStore = .shared,
        applyHandler: @escaping ApplyHandler
    ) {
        self.catalog = catalog
        self.store = store
        self.applyHandler = applyHandler
    }

    func devices(direction: AudioDeviceDirection) -> [AudioDeviceDescriptor] {
        catalog.devices(direction: direction)
    }

    func loadStartupPreference() -> AudioDeviceStartupResolution {
        let preference = store.load()
        let input = resolvePreferredUID(preference.preferredInputDeviceUID, direction: .input)
        let output = resolvePreferredUID(preference.preferredOutputDeviceUID, direction: .output)

        return AudioDeviceStartupResolution(
            preference: preference,
            resolvedInputDeviceUID: input.resolvedUID,
            resolvedOutputDeviceUID: output.resolvedUID,
            missingInputDeviceUID: input.missingUID,
            missingOutputDeviceUID: output.missingUID
        )
    }

    @MainActor
    func apply(inputUID: String?, outputUID: String?) throws -> AudioDeviceApplyResult {
        let result = try applyHandler(inputUID, outputUID)
        try store.save(
            AudioDevicePreference(
                // A deferred input selection (no armed input routing yet, so
                // the HAL apply was skipped to avoid the mic-TCC trigger) is
                // still the user's choice — persist it.
                preferredInputDeviceUID: result.appliedInputDeviceUID ?? result.deferredInputDeviceUID,
                preferredOutputDeviceUID: result.appliedOutputDeviceUID
            )
        )
        return result
    }

    private func resolvePreferredUID(
        _ uid: String?,
        direction: AudioDeviceDirection
    ) -> (resolvedUID: String?, missingUID: String?) {
        guard let uid else {
            return (catalog.defaultDeviceUID(direction: direction), nil)
        }
        guard catalog.device(uid: uid, direction: direction) != nil else {
            return (catalog.defaultDeviceUID(direction: direction), uid)
        }
        return (uid, nil)
    }
}
