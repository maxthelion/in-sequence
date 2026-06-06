import Foundation

extension Project {
    func stepOrderMap(id: StepOrderMapID) -> StepOrderMap? {
        stepOrderMaps.first { $0.id == id }
    }

    func stepOrderMapUsageCount(id: StepOrderMapID) -> Int {
        stepOrderMapDeletionStatus(id: id).assignmentCount
    }

    func stepOrderMapDeletionStatus(id: StepOrderMapID) -> StepOrderMapDeletionStatus {
        StepOrderMapDeletionStatus(
            mapID: id,
            assignedPhraseIDs: phrases.compactMap { phrase in
                phrase.stepOrderAssignment?.mapID == id ? phrase.id : nil
            }
        )
    }

    mutating func appendStepOrderMap(_ map: StepOrderMap) {
        guard map.isValid,
              stepOrderMap(id: map.id) == nil
        else {
            return
        }
        stepOrderMaps.append(map)
    }

    mutating func renameStepOrderMap(id: StepOrderMapID, name: String) {
        guard let index = stepOrderMaps.firstIndex(where: { $0.id == id }) else {
            return
        }
        stepOrderMaps[index] = stepOrderMaps[index].renamed(name)
    }

    mutating func setStepOrderMapValues(id: StepOrderMapID, values: [UInt8]) {
        guard StepOrderMap.isValidValues(values),
              let index = stepOrderMaps.firstIndex(where: { $0.id == id })
        else {
            return
        }
        stepOrderMaps[index] = stepOrderMaps[index].withValues(values)
    }

    @discardableResult
    mutating func deleteUnusedStepOrderMap(id: StepOrderMapID) -> Bool {
        guard stepOrderMapDeletionStatus(id: id).canDelete,
              let index = stepOrderMaps.firstIndex(where: { $0.id == id })
        else {
            return false
        }
        stepOrderMaps.remove(at: index)
        return true
    }

    mutating func setStepOrderAssignment(
        phraseID: UUID? = nil,
        mapID: StepOrderMapID?,
        isEnabled: Bool
    ) {
        updatePhrase(id: phraseID) { phrase in
            phrase.stepOrderAssignment = mapID.map {
                StepOrderAssignment(mapID: $0, isEnabled: isEnabled)
            }
        }
    }

    mutating func setStepOrderEnabled(_ isEnabled: Bool, phraseID: UUID? = nil) {
        updatePhrase(id: phraseID) { phrase in
            guard var assignment = phrase.stepOrderAssignment else {
                return
            }
            assignment.isEnabled = isEnabled
            phrase.stepOrderAssignment = assignment
        }
    }
}
