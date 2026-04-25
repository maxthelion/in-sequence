import Foundation

enum PresetStepper {
    enum Direction: CustomStringConvertible {
        case previous
        case next

        var description: String {
            switch self {
            case .previous:
                return "previous"
            case .next:
                return "next"
            }
        }
    }

    static func descriptors(in readout: PresetReadout) -> [AUPresetDescriptor] {
        readout.factory + readout.user
    }

    static func target(from readout: PresetReadout, direction: Direction) -> AUPresetDescriptor? {
        let presets = descriptors(in: readout)
        guard presets.count > 1 else {
            return nil
        }

        guard let currentID = readout.currentID,
              let currentIndex = presets.firstIndex(where: { $0.id == currentID })
        else {
            switch direction {
            case .previous:
                return presets.last
            case .next:
                return presets.first
            }
        }

        switch direction {
        case .previous:
            return presets[(currentIndex - 1 + presets.count) % presets.count]
        case .next:
            return presets[(currentIndex + 1) % presets.count]
        }
    }
}
