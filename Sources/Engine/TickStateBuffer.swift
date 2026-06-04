import Foundation

final class TickStateBuffer {
    struct PrepareInputs {
        let generatedStates: [UUID: GeneratedSourceEvaluationState]
        let clipCaptureService: ClipCaptureService
        let playbackSnapshot: PlaybackSnapshot
        let trackFillPreview: TrackFillPreviewPlaybackSnapshot
        let auditionOverridesByTrackID: [UUID: PseudoClipState]
    }

    private let lock = NSLock()
    private var playbackSnapshot: PlaybackSnapshot
    private var trackFillPreview: TrackFillPreviewPlaybackSnapshot = .inactive
    private var generatedStatesByTrackID: [UUID: GeneratedSourceEvaluationState] = [:]
    private var clipCaptureService = ClipCaptureService()
    private var auditionOverridesByTrackID: [UUID: PseudoClipState] = [:]
    private var preparedTickIndex: UInt64?
    private var tickIndexOnClockThread: UInt64 = 0

    init(playbackSnapshot: PlaybackSnapshot) {
        self.playbackSnapshot = playbackSnapshot
    }

    func installPlaybackSnapshot(
        _ snapshot: PlaybackSnapshot,
        currentTrackIDs: Set<UUID>? = nil,
        resetGeneratedStates: Bool = false,
        clearAuditionOverrides: Bool = false
    ) {
        withLock {
            playbackSnapshot = snapshot
            if let currentTrackIDs, let activeTrackID = trackFillPreview.activeTrackID, !currentTrackIDs.contains(activeTrackID) {
                trackFillPreview = .inactive
            }
            if let currentTrackIDs {
                clipCaptureService.removeMissingTracks(currentTrackIDs)
                auditionOverridesByTrackID = auditionOverridesByTrackID.filter { currentTrackIDs.contains($0.key) }
            }
            if clearAuditionOverrides {
                auditionOverridesByTrackID = [:]
            }
            if resetGeneratedStates {
                generatedStatesByTrackID = [:]
            }
            preparedTickIndex = nil
        }
    }

    func installTrackFillPreviewSnapshot(_ snapshot: TrackFillPreviewPlaybackSnapshot) {
        withLock {
            guard trackFillPreview != snapshot else {
                return
            }
            trackFillPreview = snapshot
            preparedTickIndex = nil
        }
    }

    func currentTrackFillPreviewSnapshot() -> TrackFillPreviewPlaybackSnapshot {
        withLock { trackFillPreview }
    }

    func currentPlaybackSnapshot() -> PlaybackSnapshot {
        withLock { playbackSnapshot }
    }

    func invalidatePreparedTick(resetGeneratedStates: Bool = false) {
        withLock {
            if resetGeneratedStates {
                generatedStatesByTrackID = [:]
            }
            preparedTickIndex = nil
        }
    }

    func resetRuntimeState(clearCapture: Bool = false) {
        withLock {
            generatedStatesByTrackID = [:]
            preparedTickIndex = nil
            auditionOverridesByTrackID = [:]
            if clearCapture {
                clipCaptureService.removeAll()
            }
        }
    }

    func hasPreparedTick() -> Bool {
        withLock { preparedTickIndex != nil }
    }

    func isPrepared(for tickIndex: UInt64) -> Bool {
        withLock { preparedTickIndex == tickIndex }
    }

    func markPreparedTick(_ tickIndex: UInt64) {
        withLock { preparedTickIndex = tickIndex }
    }

    func readPrepareInputs() -> PrepareInputs {
        withLock {
            PrepareInputs(
                generatedStates: generatedStatesByTrackID,
                clipCaptureService: clipCaptureService,
                playbackSnapshot: playbackSnapshot,
                trackFillPreview: trackFillPreview,
                auditionOverridesByTrackID: auditionOverridesByTrackID
            )
        }
    }

    func commitPrepareOutputs(
        generatedStates: [UUID: GeneratedSourceEvaluationState],
        clipCaptureService: ClipCaptureService,
        completedStep: UInt64
    ) {
        withLock {
            generatedStatesByTrackID = generatedStates
            self.clipCaptureService = clipCaptureService
            tickIndexOnClockThread = completedStep
        }
    }

    func currentClockThreadTickIndex() -> UInt64 {
        withLock { tickIndexOnClockThread }
    }

    func capturedClipContent(trackID: UUID, lengthSteps: Int? = nil) -> ClipContent? {
        withLock {
            clipCaptureService.capturedClipContent(trackID: trackID, lengthSteps: lengthSteps)
        }
    }

    func captureSnapshot(trackID: UUID) -> CaptureSnapshot {
        withLock {
            clipCaptureService.captureSnapshot(trackID: trackID)
        }
    }

    func setAuditionOverride(_ state: PseudoClipState?, for trackID: UUID) {
        withLock {
            if let state {
                auditionOverridesByTrackID[trackID] = state
            } else {
                auditionOverridesByTrackID.removeValue(forKey: trackID)
            }
            preparedTickIndex = nil
        }
    }

    @discardableResult
    func saveRollingCapture(
        to project: inout Project,
        trackID: UUID,
        destinationSlotIndex: Int? = nil,
        lengthSteps: Int? = nil,
        name: String? = nil
    ) -> UUID? {
        let captureService = withLock { clipCaptureService }
        return captureService.saveRollingCapture(
            to: &project,
            trackID: trackID,
            destinationSlotIndex: destinationSlotIndex,
            lengthSteps: lengthSteps,
            name: name
        )
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
