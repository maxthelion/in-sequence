import AudioToolbox
import AVFoundation
import Foundation

struct AudioInstrumentChoice: Codable, Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let manufacturerName: String
    let componentType: UInt32
    let componentSubType: UInt32
    let componentManufacturer: UInt32

    init(
        name: String,
        manufacturerName: String,
        componentType: UInt32,
        componentSubType: UInt32,
        componentManufacturer: UInt32
    ) {
        self.name = name
        self.manufacturerName = manufacturerName
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
    }

    var id: String {
        "\(componentType)-\(componentSubType)-\(componentManufacturer)-\(name)"
    }

    var displayName: String {
        manufacturerName.isEmpty ? name : "\(manufacturerName) \(name)"
    }

    var componentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }

    var audioComponentID: AudioComponentID {
        AudioComponentID(
            type: Self.fourCharCodeString(componentType),
            subtype: Self.fourCharCodeString(componentSubType),
            manufacturer: Self.fourCharCodeString(componentManufacturer),
            version: 0
        )
    }

    static let builtInSynth = AudioInstrumentChoice(
        name: "DLS Synth",
        manufacturerName: "Apple",
        componentType: kAudioUnitType_MusicDevice,
        componentSubType: kAudioUnitSubType_DLSSynth,
        componentManufacturer: kAudioUnitManufacturer_Apple
    )

    static let testInstrument = AudioInstrumentChoice(
        name: "Test Synth",
        manufacturerName: "Codex",
        componentType: kAudioUnitType_MusicDevice,
        componentSubType: 0x54455354,
        componentManufacturer: 0x43445820
    )

    static var defaultChoices: [AudioInstrumentChoice] {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        let manager = AVAudioUnitComponentManager.shared()
        var choices = manager.components(matching: description).map {
            AudioInstrumentChoice(
                name: $0.name,
                manufacturerName: $0.manufacturerName,
                componentType: $0.audioComponentDescription.componentType,
                componentSubType: $0.audioComponentDescription.componentSubType,
                componentManufacturer: $0.audioComponentDescription.componentManufacturer
            )
        }

        if !choices.contains(builtInSynth) {
            choices.insert(builtInSynth, at: 0)
        }

#if DEBUG
        if !choices.contains(testInstrument) {
            choices.append(testInstrument)
        }
#endif

        return choices.sorted { lhs, rhs in
            if lhs == builtInSynth { return true }
            if rhs == builtInSynth { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    init(audioComponentID: AudioComponentID, name: String = "External AU", manufacturerName: String = "") {
        self.name = name
        self.manufacturerName = manufacturerName
        self.componentType = Self.fourCharCodeValue(audioComponentID.type)
        self.componentSubType = Self.fourCharCodeValue(audioComponentID.subtype)
        self.componentManufacturer = Self.fourCharCodeValue(audioComponentID.manufacturer)
    }

    static func fourCharCodeString(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "????"
    }

    static func fourCharCodeValue(_ string: String) -> UInt32 {
        let padded = string.padding(toLength: 4, withPad: " ", startingAt: 0)
        return padded.utf8.prefix(4).reduce(0) { partial, byte in
            (partial << 8) + UInt32(byte)
        }
    }
}
