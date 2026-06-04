import Foundation

enum TrackFillPreviewResetReason: Equatable, Sendable {
    case documentChanged
    case selectedTrackUnavailable
    case userCleared
}

struct TrackFillPreviewState: Equatable, Sendable {
    var activeTrackID: UUID?

    static let inactive = TrackFillPreviewState(activeTrackID: nil)

    var playbackSnapshot: TrackFillPreviewPlaybackSnapshot {
        TrackFillPreviewPlaybackSnapshot(activeTrackID: activeTrackID)
    }

    func isActive(for trackID: UUID) -> Bool {
        activeTrackID == trackID
    }
}

struct TrackFillPreviewPlaybackSnapshot: Equatable, Sendable {
    let activeTrackID: UUID?

    static let inactive = TrackFillPreviewPlaybackSnapshot(activeTrackID: nil)

    func isActive(for trackID: UUID) -> Bool {
        activeTrackID == trackID
    }
}
