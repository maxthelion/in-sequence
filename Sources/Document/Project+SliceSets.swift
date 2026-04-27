import Foundation

extension Project {
    func sliceSet(id: UUID?) -> SliceSet? {
        guard let id else { return nil }
        if id == SliceSet.emptyID {
            return SliceSet.empty
        }
        return sliceSetPool.first(where: { $0.id == id })
    }

    func firstSliceSet(for sampleID: UUID) -> SliceSet? {
        sliceSetPool.first(where: { $0.sampleID == sampleID })
    }

    mutating func addSliceSet(_ set: SliceSet) {
        guard set.id != SliceSet.emptyID else { return }
        if let index = sliceSetPool.firstIndex(where: { $0.id == set.id }) {
            sliceSetPool[index] = set
        } else {
            sliceSetPool.append(set)
        }
    }

    mutating func removeSliceSet(id: UUID) {
        guard id != SliceSet.emptyID else { return }
        sliceSetPool.removeAll { $0.id == id }
        for trackIndex in tracks.indices {
            if case let .slicer(sliceSetID, _) = tracks[trackIndex].destination,
               sliceSetID == id
            {
                tracks[trackIndex].destination = .slicer(sliceSetID: SliceSet.emptyID, settings: .default)
            }
        }
    }

    mutating func updateSliceSet(id: UUID, _ update: (inout SliceSet) -> Void) {
        guard id != SliceSet.emptyID,
              let index = sliceSetPool.firstIndex(where: { $0.id == id })
        else {
            return
        }
        update(&sliceSetPool[index])
    }
}
