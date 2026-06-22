import Foundation

extension SequencerDocumentSession {
    func enableSelectedTrackFillPreview() {
        let trackID = store.selectedTrackID
        guard store.tracks.contains(where: { $0.id == trackID }) else {
            clearTrackFillPreview(reason: .selectedTrackUnavailable)
            return
        }
        guard isTrackFillPreviewAvailable(trackID: trackID) else {
            clearTrackFillPreview(reason: .sourceBecameUnsupported)
            return
        }
        setTrackFillPreviewActiveTrackID(trackID)
    }

    func disableTrackFillPreview(for trackID: UUID) {
        guard trackFillPreviewState.activeTrackID == trackID else {
            return
        }
        setTrackFillPreviewActiveTrackID(nil)
    }

    /// Toggle fill preview for an explicit track id (used by the kit matrix's
    /// kit-level FILL/NORMAL control, which addresses the kit's representative
    /// member rather than the document's selected track). When `active` is true
    /// and the track's source supports it, the fill lane becomes the active
    /// preview; otherwise the preview is cleared back to NORMAL playback.
    func setTrackFillPreview(trackID: UUID, active: Bool) {
        guard active else {
            disableTrackFillPreview(for: trackID)
            return
        }
        guard store.tracks.contains(where: { $0.id == trackID }) else {
            clearTrackFillPreview(reason: .selectedTrackUnavailable)
            return
        }
        guard isTrackFillPreviewAvailable(trackID: trackID) else {
            clearTrackFillPreview(reason: .sourceBecameUnsupported)
            return
        }
        setTrackFillPreviewActiveTrackID(trackID)
    }

    /// Whether fill preview is currently the active lane for the given track.
    func isTrackFillPreviewActive(trackID: UUID) -> Bool {
        trackFillPreviewState.isActive(for: trackID)
    }

    func clearTrackFillPreview(reason _: TrackFillPreviewResetReason) {
        setTrackFillPreviewActiveTrackID(nil)
    }

    func isTrackFillPreviewAvailable(trackID: UUID) -> Bool {
        let pattern = store.selectedPattern(for: trackID)
        guard pattern.sourceRef.mode == .clip else {
            return false
        }
        return store.clipEntry(id: pattern.sourceRef.clipID) != nil
    }

    func clearTrackFillPreviewIfActiveTrack(_ trackID: UUID, reason: TrackFillPreviewResetReason) {
        guard trackFillPreviewState.activeTrackID == trackID else {
            return
        }
        clearTrackFillPreview(reason: reason)
    }

    private func setTrackFillPreviewActiveTrackID(_ trackID: UUID?) {
        let nextState = TrackFillPreviewState(activeTrackID: trackID)
        guard trackFillPreviewState != nextState else {
            return
        }
        trackFillPreviewState = nextState
        engineController.apply(trackFillPreview: nextState.playbackSnapshot)
    }
}
