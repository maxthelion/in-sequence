import Foundation

struct ClipCaptureService: Equatable {
    private struct RollingCaptureStep: Equatable {
        let absoluteStep: Int
        let notes: [GeneratedNote]
    }

    private struct RollingCaptureBuffer: Equatable {
        let maxSteps: Int
        var steps: [RollingCaptureStep]

        init(maxSteps: Int, steps: [RollingCaptureStep] = []) {
            self.maxSteps = max(1, maxSteps)
            self.steps = Array(steps.suffix(max(1, maxSteps)))
        }

        mutating func append(stepIndex: Int, notes: [GeneratedNote]) {
            let entry = RollingCaptureStep(absoluteStep: stepIndex, notes: notes)
            if let lastIndex = steps.indices.last, steps[lastIndex].absoluteStep == stepIndex {
                steps[lastIndex] = entry
            } else {
                steps.append(entry)
            }

            if steps.count > maxSteps {
                steps.removeFirst(steps.count - maxSteps)
            }
        }

        func clipContent(lengthSteps: Int? = nil) -> ClipContent? {
            guard !steps.isEmpty else {
                return nil
            }

            let resolvedLength = max(1, lengthSteps ?? min(maxSteps, steps.count))
            let recent = Array(steps.suffix(resolvedLength))
            let paddingCount = max(0, resolvedLength - recent.count)
            let capturedSteps = recent.map { recordedStep -> ClipStep in
                guard !recordedStep.notes.isEmpty else {
                    return .empty
                }

                let notes = recordedStep.notes.map { note in
                    ClipStepNote(
                        pitch: note.pitch,
                        velocity: note.velocity,
                        lengthSteps: max(1, note.length)
                    )
                }
                return ClipStep(main: ClipLane(chance: 1, notes: notes), fill: nil)
            }

            return .noteGrid(
                lengthSteps: resolvedLength,
                steps: Array(repeating: .empty, count: paddingCount) + capturedSteps
            )
        }

        func captureSnapshot() -> CaptureSnapshot {
            CaptureSnapshot(
                maxSteps: maxSteps,
                steps: steps.map { step in
                    CaptureSnapshot.Step(
                        absoluteStep: step.absoluteStep,
                        notes: step.notes.map(CaptureSnapshot.Note.init)
                    )
                }
            )
        }
    }

    private let maxSteps: Int
    private var buffersByTrackID: [UUID: RollingCaptureBuffer]

    init(maxSteps: Int = 256) {
        self.maxSteps = max(1, maxSteps)
        self.buffersByTrackID = [:]
    }

    mutating func append(trackID: UUID, stepIndex: Int, notes: [GeneratedNote]) {
        var buffer = buffersByTrackID[trackID] ?? RollingCaptureBuffer(maxSteps: maxSteps)
        buffer.append(stepIndex: stepIndex, notes: notes)
        buffersByTrackID[trackID] = buffer
    }

    func capturedClipContent(trackID: UUID, lengthSteps: Int? = nil) -> ClipContent? {
        buffersByTrackID[trackID]?.clipContent(lengthSteps: lengthSteps)
    }

    func captureSnapshot(trackID: UUID) -> CaptureSnapshot {
        buffersByTrackID[trackID]?.captureSnapshot() ?? CaptureSnapshot(maxSteps: maxSteps)
    }

    @discardableResult
    func saveRollingCapture(
        to project: inout Project,
        trackID: UUID,
        destinationSlotIndex: Int? = nil,
        lengthSteps: Int? = nil,
        name: String? = nil
    ) -> UUID? {
        guard let content = capturedClipContent(trackID: trackID, lengthSteps: lengthSteps) else {
            return nil
        }

        return project.saveCapturedClip(
            content,
            trackID: trackID,
            destinationSlotIndex: destinationSlotIndex,
            name: name
        )
    }

    mutating func removeMissingTracks(_ currentTrackIDs: Set<UUID>) {
        buffersByTrackID = buffersByTrackID.filter { currentTrackIDs.contains($0.key) }
    }

    mutating func removeAll() {
        buffersByTrackID = [:]
    }
}
