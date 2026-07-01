import Foundation

final class TickStateBuffer {
    struct PrepareInputs {
        let generatedStates: [UUID: GeneratedSourceEvaluationState]
        let clipCaptureService: ClipCaptureService
        let playbackSnapshot: PlaybackSnapshot
        let trackFillPreview: TrackFillPreviewPlaybackSnapshot
        let auditionOverridesByTrackID: [UUID: PseudoClipState]
        /// Round-2 Phase-2: a monotonically-increasing revision bumped on every
        /// generation-input change (snapshot install, audition override, fill
        /// preview). The off-thread bar precompute keys on this so a stale bar for
        /// a superseded snapshot is invalidated (never consumed) even when the
        /// `(phraseID, bar-start)` is unchanged (e.g. an in-place pattern edit).
        let generationInputRevision: UInt64
    }

    private let lock = NSLock()
    private var playbackSnapshot: PlaybackSnapshot
    private var trackFillPreview: TrackFillPreviewPlaybackSnapshot = .inactive
    private var generatedStatesByTrackID: [UUID: GeneratedSourceEvaluationState] = [:]
    private var clipCaptureService = ClipCaptureService()
    private var auditionOverridesByTrackID: [UUID: PseudoClipState] = [:]
    private var preparedTickIndex: UInt64?
    private var tickIndexOnClockThread: UInt64 = 0
    /// Bumped under `lock` on every generation-input change (see PrepareInputs).
    private var generationInputRevision: UInt64 = 0

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
            generationInputRevision &+= 1
        }
    }

    func installTrackFillPreviewSnapshot(_ snapshot: TrackFillPreviewPlaybackSnapshot) {
        withLock {
            guard trackFillPreview != snapshot else {
                return
            }
            trackFillPreview = snapshot
            preparedTickIndex = nil
            generationInputRevision &+= 1
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
            generationInputRevision &+= 1
        }
    }

    func resetRuntimeState(clearCapture: Bool = false) {
        withLock {
            generatedStatesByTrackID = [:]
            preparedTickIndex = nil
            auditionOverridesByTrackID = [:]
            generationInputRevision &+= 1
            if clearCapture {
                clipCaptureService.removeAll()
            }
        }
    }

    func hasPreparedTick() -> Bool {
        withLock { preparedTickIndex != nil }
    }

    func currentPreparedTickIndex() -> UInt64? {
        withLock { preparedTickIndex }
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
                auditionOverridesByTrackID: auditionOverridesByTrackID,
                generationInputRevision: generationInputRevision
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

    /// The current generation-input revision (see `PrepareInputs`). Read fresh on
    /// the tick path AFTER any in-tick snapshot mutation (e.g. a phrase-boundary
    /// step-order commit) so the off-thread precompute keys on the just-installed
    /// snapshot, never a stale pre-mutation bar.
    func currentGenerationInputRevision() -> UInt64 {
        withLock { generationInputRevision }
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
            generationInputRevision &+= 1
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
