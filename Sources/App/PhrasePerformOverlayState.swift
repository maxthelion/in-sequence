import Foundation

struct PhrasePerformOverlayCellKey: Hashable, Sendable {
    var layerID: String
    var trackID: UUID
}
struct PhrasePerformOverlayAssignment: Equatable, Sendable {
    var layerID: String
    var trackID: UUID
    var cell: PhraseCell
}

struct PhrasePerformOverlayState: Equatable, Sendable {
    private(set) var basisPhraseID: UUID?
    private var cellsByKey: [PhrasePerformOverlayCellKey: PhraseCell] = [:]

    var isDirty: Bool {
        basisPhraseID != nil && !cellsByKey.isEmpty
    }

    var stagedCellCount: Int {
        cellsByKey.count
    }

    var stagedAssignments: [PhrasePerformOverlayAssignment] {
        cellsByKey
            .map { key, cell in
                PhrasePerformOverlayAssignment(layerID: key.layerID, trackID: key.trackID, cell: cell)
            }
            .sorted { lhs, rhs in
                if lhs.layerID != rhs.layerID {
                    return lhs.layerID < rhs.layerID
                }
                return lhs.trackID.uuidString < rhs.trackID.uuidString
            }
    }

    func blocksBasisSwitch(to phraseID: UUID) -> Bool {
        guard isDirty, let basisPhraseID else {
            return false
        }
        return basisPhraseID != phraseID
    }

    func cell(phraseID: UUID, layerID: String, trackID: UUID) -> PhraseCell? {
        guard isDirty, basisPhraseID == phraseID else {
            return nil
        }
        return cellsByKey[PhrasePerformOverlayCellKey(layerID: layerID, trackID: trackID)]
    }

    mutating func stage(
        _ cell: PhraseCell,
        basisPhraseID nextBasisPhraseID: UUID,
        layerID: String,
        trackIDs: [UUID]
    ) -> Bool {
        if isDirty, basisPhraseID != nextBasisPhraseID {
            return false
        }

        basisPhraseID = nextBasisPhraseID

        var changed = false
        for trackID in trackIDs {
            let key = PhrasePerformOverlayCellKey(layerID: layerID, trackID: trackID)
            guard cellsByKey[key] != cell else {
                continue
            }
            cellsByKey[key] = cell
            changed = true
        }
        return changed
    }

    mutating func clear() {
        basisPhraseID = nil
        cellsByKey.removeAll()
    }

    mutating func reconcile(availablePhraseIDs: some Collection<UUID>) -> Bool {
        guard let basisPhraseID,
              !availablePhraseIDs.contains(basisPhraseID)
        else {
            return false
        }
        clear()
        return true
    }

    func applying(to phrase: PhraseModel) -> PhraseModel {
        guard isDirty, basisPhraseID == phrase.id else {
            return phrase
        }

        var stagedPhrase = phrase
        for assignment in stagedAssignments {
            stagedPhrase.setCell(assignment.cell, for: assignment.layerID, trackID: assignment.trackID)
        }
        return stagedPhrase
    }
}
