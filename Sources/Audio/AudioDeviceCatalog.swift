import CoreAudio
import Foundation

enum AudioDeviceDirection: String, CaseIterable, Codable, Sendable {
    case input
    case output

    var displayName: String {
        switch self {
        case .input: "Input"
        case .output: "Output"
        }
    }

    var coreAudioScope: AudioObjectPropertyScope {
        switch self {
        case .input: kAudioDevicePropertyScopeInput
        case .output: kAudioDevicePropertyScopeOutput
        }
    }

    var defaultDeviceSelector: AudioObjectPropertySelector {
        switch self {
        case .input: kAudioHardwarePropertyDefaultInputDevice
        case .output: kAudioHardwarePropertyDefaultOutputDevice
        }
    }
}

struct AudioDeviceDescriptor: Equatable, Identifiable, Sendable {
    var uid: String
    var displayName: String
    var direction: AudioDeviceDirection
    var channelCount: Int

    var id: String { "\(direction.rawValue):\(uid)" }
}

enum AudioDeviceCatalogError: Error, Equatable, LocalizedError {
    case coreAudioStatus(OSStatus, String)
    case missingDeviceUID(String, AudioDeviceDirection)
    case missingDefaultDevice(AudioDeviceDirection)

    var errorDescription: String? {
        switch self {
        case let .coreAudioStatus(status, operation):
            "\(operation) failed with CoreAudio status \(status)."
        case let .missingDeviceUID(uid, direction):
            "The preferred \(direction.rawValue) device '\(uid)' is not connected."
        case let .missingDefaultDevice(direction):
            "No system default \(direction.rawValue) device is available."
        }
    }
}

protocol AudioDeviceCataloging {
    func devices(direction: AudioDeviceDirection) -> [AudioDeviceDescriptor]
    func device(uid: String, direction: AudioDeviceDirection) -> AudioDeviceDescriptor?
    func defaultDeviceUID(direction: AudioDeviceDirection) -> String?
}

protocol AudioHardwareDeviceResolving: AudioDeviceCataloging {
    func deviceID(for uid: String, direction: AudioDeviceDirection) throws -> AudioDeviceID
    func defaultDeviceID(direction: AudioDeviceDirection) throws -> AudioDeviceID
    func deviceUID(for deviceID: AudioDeviceID) -> String?
}

final class CoreAudioDeviceCatalog: AudioHardwareDeviceResolving {
    func devices(direction: AudioDeviceDirection) -> [AudioDeviceDescriptor] {
        (try? allDeviceIDs())?
            .compactMap { descriptor(for: $0, direction: direction) }
            .filter { $0.channelCount > 0 }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            } ?? []
    }

    func device(uid: String, direction: AudioDeviceDirection) -> AudioDeviceDescriptor? {
        devices(direction: direction).first { $0.uid == uid }
    }

    func defaultDeviceUID(direction: AudioDeviceDirection) -> String? {
        guard let deviceID = try? defaultDeviceID(direction: direction) else {
            return nil
        }
        return deviceUID(for: deviceID)
    }

    func deviceID(for uid: String, direction: AudioDeviceDirection) throws -> AudioDeviceID {
        for deviceID in try allDeviceIDs() {
            guard deviceUID(for: deviceID) == uid else { continue }
            guard channelCount(for: deviceID, direction: direction) > 0 else { continue }
            return deviceID
        }
        throw AudioDeviceCatalogError.missingDeviceUID(uid, direction)
    }

    func defaultDeviceID(direction: AudioDeviceDirection) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: direction.defaultDeviceSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        try Self.throwIfNeeded(status, operation: "Read default \(direction.rawValue) device")
        guard deviceID != kAudioObjectUnknown else {
            throw AudioDeviceCatalogError.missingDefaultDevice(direction)
        }
        return deviceID
    }

    /// Channel count of the system-default input device via plain HAL property
    /// reads (`kAudioDevicePropertyStreamConfiguration`). This neither creates
    /// nor arms any IO unit, so — unlike `AVAudioEngine.inputNode`, whose first
    /// access permanently enables the shared IO unit's input scope — it can be
    /// used for UI affordances without ever becoming a microphone-TCC trigger.
    /// Returns 0 when no default input device exists.
    func defaultInputDeviceChannelCount() -> Int {
        guard let deviceID = try? defaultDeviceID(direction: .input) else { return 0 }
        return channelCount(for: deviceID, direction: .input)
    }

    func deviceUID(for deviceID: AudioDeviceID) -> String? {
        stringProperty(
            kAudioDevicePropertyDeviceUID,
            objectID: deviceID,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private func allDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        try Self.throwIfNeeded(status, operation: "Read audio device list size")

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        )
        try Self.throwIfNeeded(status, operation: "Read audio device list")
        return devices
    }

    private func descriptor(for deviceID: AudioDeviceID, direction: AudioDeviceDirection) -> AudioDeviceDescriptor? {
        guard let uid = deviceUID(for: deviceID) else { return nil }
        let channels = channelCount(for: deviceID, direction: direction)
        guard channels > 0 else { return nil }
        let displayName = stringProperty(
            kAudioObjectPropertyName,
            objectID: deviceID,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? uid

        return AudioDeviceDescriptor(
            uid: uid,
            displayName: displayName,
            direction: direction,
            channelCount: channels
        )
    }

    private func channelCount(for deviceID: AudioDeviceID, direction: AudioDeviceDirection) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: direction.coreAudioScope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard sizeStatus == noErr, size > 0 else { return 0 }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }

        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        let dataStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, list)
        guard dataStatus == noErr else { return 0 }

        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { total, buffer in
            total + Int(buffer.mNumberChannels)
        }
    }

    private func stringProperty(
        _ selector: AudioObjectPropertySelector,
        objectID: AudioObjectID,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value as String?
    }

    static func throwIfNeeded(_ status: OSStatus, operation: String) throws {
        guard status != noErr else { return }
        throw AudioDeviceCatalogError.coreAudioStatus(status, operation)
    }
}
