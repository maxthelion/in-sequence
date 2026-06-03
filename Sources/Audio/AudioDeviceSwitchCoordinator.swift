import CoreAudio
import Foundation

struct AudioDeviceApplyResult: Equatable, Sendable {
    var appliedInputDeviceUID: String?
    var appliedOutputDeviceUID: String?
    var wasRunningBeforeApply: Bool
    var restartedEngine: Bool
}

struct AudioDeviceOwnerApplyResult: Equatable, Sendable {
    var appliedInputDeviceUID: String?
    var appliedOutputDeviceUID: String?
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

final class CoreAudioDefaultDeviceOwner: AudioDeviceOwning {
    private let catalog: CoreAudioDeviceCatalog

    init(catalog: CoreAudioDeviceCatalog = CoreAudioDeviceCatalog()) {
        self.catalog = catalog
    }

    func activeDeviceUID(direction: AudioDeviceDirection) -> String? {
        catalog.defaultDeviceUID(direction: direction)
    }

    func apply(inputUID: String?, outputUID: String?) throws -> AudioDeviceOwnerApplyResult {
        let previousInputDeviceID = try? catalog.defaultDeviceID(direction: .input)
        let previousOutputDeviceID = try? catalog.defaultDeviceID(direction: .output)

        do {
            let targetInputDeviceID = try targetDeviceID(preferredUID: inputUID, direction: .input)
            let targetOutputDeviceID = try targetDeviceID(preferredUID: outputUID, direction: .output)

            if let targetInputDeviceID {
                try setDefaultDeviceID(targetInputDeviceID, direction: .input)
            }
            if let targetOutputDeviceID {
                try setDefaultDeviceID(targetOutputDeviceID, direction: .output)
            }

            return AudioDeviceOwnerApplyResult(
                appliedInputDeviceUID: try verifiedActiveUID(targetInputDeviceID, direction: .input),
                appliedOutputDeviceUID: try verifiedActiveUID(targetOutputDeviceID, direction: .output)
            )
        } catch {
            let rollbackError = rollback(
                inputDeviceID: previousInputDeviceID,
                outputDeviceID: previousOutputDeviceID
            )
            throw AudioDeviceApplyError.rollbackPerformed(underlying: error, rollbackError: rollbackError)
        }
    }

    private func targetDeviceID(preferredUID: String?, direction: AudioDeviceDirection) throws -> AudioDeviceID? {
        if let preferredUID {
            return try catalog.deviceID(for: preferredUID, direction: direction)
        }
        return try? catalog.defaultDeviceID(direction: direction)
    }

    private func setDefaultDeviceID(_ deviceID: AudioDeviceID, direction: AudioDeviceDirection) throws {
        guard (try? catalog.defaultDeviceID(direction: direction)) != deviceID else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: direction.defaultDeviceSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )
        try CoreAudioDeviceCatalog.throwIfNeeded(status, operation: "Set default \(direction.rawValue) device")
    }

    private func verifiedActiveUID(_ targetDeviceID: AudioDeviceID?, direction: AudioDeviceDirection) throws -> String? {
        guard let targetDeviceID else { return nil }
        let expectedUID = catalog.deviceUID(for: targetDeviceID)
        let actualUID = catalog.defaultDeviceUID(direction: direction)
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
                try setDefaultDeviceID(inputDeviceID, direction: .input)
            }
            if let outputDeviceID {
                try setDefaultDeviceID(outputDeviceID, direction: .output)
            }
            return nil
        } catch {
            return error
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
                preferredInputDeviceUID: result.appliedInputDeviceUID,
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
