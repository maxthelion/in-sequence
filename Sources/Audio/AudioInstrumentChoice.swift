import AudioToolbox
import AVFoundation
import Foundation

struct AudioInstrumentChoice: Codable, Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let manufacturerName: String
    let componentType: UInt32
    let componentSubType: UInt32
    let componentManufacturer: UInt32

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

        return choices.sorted { lhs, rhs in
            if lhs == builtInSynth { return true }
            if rhs == builtInSynth { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
