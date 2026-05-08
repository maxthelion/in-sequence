import Foundation

extension SequencerDocumentSession {
    @discardableResult
    func createBlankModifierGenerator(trackID: UUID, slotIndex: Int) -> GeneratorPoolEntry? {
        var created: GeneratorPoolEntry?
        batch(impact: .snapshotOnly, changed: .full) { store in
            var project = store.exportToProject()
            created = project.createBlankModifierGenerator(trackID: trackID, slotIndex: slotIndex)
            guard let bank = project.patternBanks.first(where: { $0.trackID == trackID }) else {
                return
            }
            if let created {
                store.appendGenerator(created)
            }
            store.setPatternBank(trackID: trackID, bank: bank)
        }
        return created
    }

    func assignModifierGenerator(_ modifierGeneratorID: UUID, to trackID: UUID, slotIndex: Int) {
        batch(impact: .snapshotOnly, changed: .patternBank(trackID)) { store in
            var project = store.exportToProject()
            project.assignModifierGenerator(modifierGeneratorID, to: trackID, slotIndex: slotIndex)
            guard let bank = project.patternBanks.first(where: { $0.trackID == trackID }) else {
                return
            }
            store.setPatternBank(trackID: trackID, bank: bank)
        }
    }
}
