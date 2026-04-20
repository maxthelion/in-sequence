import Foundation

extension DrumKitPreset {
    var suggestedSharedDestination: Destination {
        .internalSampler(bankID: .drumKitDefault, preset: rawValue)
    }
}
