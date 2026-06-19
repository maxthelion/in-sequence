import Foundation

/// Per-track FX insert chain mutations (track-view IA, AC4).
///
/// The chain lives on `StepSequenceTrack.fxInserts` and is edited through the
/// FX tab. These mutations mirror the bus/scene insert mutation shape but
/// operate on a track. Engine application of the chain is a follow-up (see the
/// TODO in `fxTab`); these mutations only persist + drive the UI today.
extension SequencerDocumentSession {
    /// Append a new insert to the end of a track's FX chain.
    @discardableResult
    func addFXInsert(trackID: UUID, insert: TrackFXInsert) -> Bool {
        mutateTrack(id: trackID) { track in
            track.fxInserts.append(insert.normalized())
        }
    }

    /// Remove an insert from a track's FX chain by id.
    @discardableResult
    func removeFXInsert(trackID: UUID, insertID: UUID) -> Bool {
        mutateTrack(id: trackID) { track in
            track.fxInserts.removeAll { $0.id == insertID }
        }
    }

    /// Reorder a track's FX chain (used by the drag-handle / `.onMove`).
    @discardableResult
    func moveFXInsert(trackID: UUID, from source: IndexSet, to destination: Int) -> Bool {
        mutateTrack(id: trackID) { track in
            track.fxInserts.move(fromOffsets: source, toOffset: destination)
        }
    }

    /// Set an insert's bypass state.
    @discardableResult
    func setFXInsertBypassed(trackID: UUID, insertID: UUID, bypassed: Bool) -> Bool {
        mutateTrack(id: trackID) { track in
            guard let index = track.fxInserts.firstIndex(where: { $0.id == insertID }) else {
                return
            }
            track.fxInserts[index].bypassed = bypassed
        }
    }
}
