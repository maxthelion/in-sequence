import Foundation

/// Per-track FX insert chain mutations (track-view IA, AC4).
///
/// The chain lives on `StepSequenceTrack.fxInserts` and is edited through the
/// FX tab. These mutations mirror the bus/scene insert mutation shape but
/// operate on a track.
///
/// Engine application: each mutation dispatches a `.scopedRuntime(.trackInserts)`
/// update rather than `apply(documentModel:)`. The graph splices the chain
/// between the track's output node and its dry/sends destinations and applies a
/// value-only fast path for bypass-style edits (engine stays running) —
/// matching the bus/send scoped-FX shape (Performance-Time Mutation Rule). The
/// `.none` snapshot change avoids a note-buffer recompile (FX inserts do not
/// change compiled note data; the engine hears the chain through the scoped
/// path immediately).
extension SequencerDocumentSession {
    /// Append a new insert to the end of a track's FX chain.
    @discardableResult
    func addFXInsert(trackID: UUID, insert: TrackFXInsert) -> Bool {
        mutateTrackFXInserts(trackID: trackID) { inserts in
            inserts.append(insert.normalized())
        }
    }

    /// Remove an insert from a track's FX chain by id.
    @discardableResult
    func removeFXInsert(trackID: UUID, insertID: UUID) -> Bool {
        mutateTrackFXInserts(trackID: trackID) { inserts in
            inserts.removeAll { $0.id == insertID }
        }
    }

    /// Reorder a track's FX chain (used by the drag-handle / `.onMove`).
    @discardableResult
    func moveFXInsert(trackID: UUID, from source: IndexSet, to destination: Int) -> Bool {
        mutateTrackFXInserts(trackID: trackID) { inserts in
            inserts.move(fromOffsets: source, toOffset: destination)
        }
    }

    /// Set an insert's bypass state.
    @discardableResult
    func setFXInsertBypassed(trackID: UUID, insertID: UUID, bypassed: Bool) -> Bool {
        mutateTrackFXInserts(trackID: trackID) { inserts in
            guard let index = inserts.firstIndex(where: { $0.id == insertID }) else {
                return
            }
            inserts[index].bypassed = bypassed
        }
    }
}
