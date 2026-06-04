import Foundation

extension SequencerDocumentSession {
    func enableSelectedTrackFillPreview() {
        let trackID = store.selectedTrackID
        guard store.tracks.contains(where: { $0.id == trackID }) else {
            clearTrackFillPreview(reason: .selectedTrackUnavailable)
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

    func clearTrackFillPreview(reason _: TrackFillPreviewResetReason) {
        setTrackFillPreviewActiveTrackID(nil)
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
