import Foundation

final class TickStateBuffer {
    struct PrepareInputs {
        let generatedStates: [UUID: GeneratedSourceEvaluationState]
        let clipCaptureService: ClipCaptureService
        let playbackSnapshot: PlaybackSnapshot
    }

    private let lock = NSLock()
    private var playbackSnapshot: PlaybackSnapshot
    private var generatedStatesByTrackID: [UUID: GeneratedSourceEvaluationState] = [:]
    private var clipCaptureService = ClipCaptureService()
    private var preparedTickIndex: UInt64?
    private var tickIndexOnClockThread: UInt64 = 0

    init(playbackSnapshot: PlaybackSnapshot) {
        self.playbackSnapshot = playbackSnapshot
    }

    func installPlaybackSnapshot(
        _ snapshot: PlaybackSnapshot,
        currentTrackIDs: Set<UUID>? = nil,
        resetGeneratedStates: Bool = false
    ) {
        withLock {
            playbackSnapshot = snapshot
            if let currentTrackIDs {
                clipCaptureService.removeMissingTracks(currentTrackIDs)
            }
            if resetGeneratedStates {
                generatedStatesByTrackID = [:]
            }
            preparedTickIndex = nil
        }
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
                playbackSnapshot: playbackSnapshot
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
