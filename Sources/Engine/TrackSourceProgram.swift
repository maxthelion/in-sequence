import Foundation

enum SlotProgram: Equatable, Sendable {
    case clip(clipID: UUID, modifierGeneratorID: UUID?, modifierBypassed: Bool)
    case generator(generatorID: UUID, modifierGeneratorID: UUID?, modifierBypassed: Bool)
    case empty
}

struct TrackSourceProgram: Equatable, Sendable {
    let trackID: UUID
    let generatorBlockID: BlockID
    let slotPrograms: [SlotProgram]
    let macroBindingIDs: [UUID]
}
