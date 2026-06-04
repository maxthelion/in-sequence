import Foundation

struct TrackPerformSelectionState: Equatable {
    private(set) var selectedTrackIDs: Set<UUID>

    init(selectedTrackIDs: Set<UUID> = []) {
        self.selectedTrackIDs = selectedTrackIDs
    }

    var count: Int {
        selectedTrackIDs.count
    }

    var isEmpty: Bool {
        selectedTrackIDs.isEmpty
    }

    func contains(_ trackID: UUID) -> Bool {
        selectedTrackIDs.contains(trackID)
    }

    mutating func add(_ trackID: UUID) {
        selectedTrackIDs.insert(trackID)
    }

    mutating func remove(_ trackID: UUID) {
        selectedTrackIDs.remove(trackID)
    }

    mutating func toggle(_ trackID: UUID) {
        if selectedTrackIDs.contains(trackID) {
            selectedTrackIDs.remove(trackID)
        } else {
            selectedTrackIDs.insert(trackID)
        }
    }

    mutating func clear() {
        selectedTrackIDs.removeAll()
    }

    mutating func reconcile(availableTrackIDs: [UUID]) {
        selectedTrackIDs.formIntersection(Set(availableTrackIDs))
    }
}

enum TrackPerformAuthoredEdit {
    static func recipientTrackIDs(
        sourceTrackID: UUID,
        orderedTrackIDs: [UUID],
        selection: TrackPerformSelectionState
    ) -> [UUID] {
        guard selection.count >= 2, selection.contains(sourceTrackID) else {
            return [sourceTrackID]
        }

        let recipients = orderedTrackIDs.filter { selection.contains($0) }
        return recipients.isEmpty ? [sourceTrackID] : recipients
    }
}
