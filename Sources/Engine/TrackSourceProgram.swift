import Foundation

enum SlotProgram: Equatable, Sendable {
    case clip(clipID: UUID, modifierGeneratorID: UUID?, modifierBypassed: Bool)
    case generator(generatorID: UUID, modifierGeneratorID: UUID?, modifierBypassed: Bool)
    case empty
}

struct TrackSourceProgram: Equatable, Sendable {
    let trackID: UUID
    let slotPrograms: [SlotProgram]
    let macroBindingIDs: [UUID]
    let macroDefaults: [UUID: Double]

    func slotProgram(at slotIndex: Int) -> SlotProgram {
        guard !slotPrograms.isEmpty else {
            return .empty
        }
        let normalizedIndex = min(max(slotIndex, 0), slotPrograms.count - 1)
        return slotPrograms[normalizedIndex]
    }
}
