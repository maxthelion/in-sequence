import Foundation

struct PseudoClipState: Equatable, Sendable {
    static let supportedLengthSteps = [8, 16, 32, 64]

    let sourceTrackID: UUID
    let startStep: Int
    let lengthSteps: Int
    let noteGrid: ClipContent

    static func materialize(
        sourceTrackID: UUID,
        from snapshot: CaptureSnapshot,
        startStep: Int,
        lengthSteps: Int
    ) -> PseudoClipState {
        let resolvedLength = resolvedLengthSteps(lengthSteps, maxSteps: snapshot.maxSteps)
        let boundedStart = resolvedStartStep(startStep, lengthSteps: resolvedLength, maxSteps: snapshot.maxSteps)
        let noteGrid = materializedNoteGrid(
            from: snapshot,
            startStep: boundedStart,
            lengthSteps: resolvedLength
        )

        return PseudoClipState(
            sourceTrackID: sourceTrackID,
            startStep: boundedStart,
            lengthSteps: resolvedLength,
            noteGrid: noteGrid
        )
    }

    static func materializedNoteGrid(
        from snapshot: CaptureSnapshot,
        startStep: Int,
        lengthSteps: Int
    ) -> ClipContent {
        let resolvedLength = resolvedLengthSteps(lengthSteps, maxSteps: snapshot.maxSteps)
        let boundedStart = resolvedStartStep(startStep, lengthSteps: resolvedLength, maxSteps: snapshot.maxSteps)

        guard let lastAbsoluteStep = snapshot.steps.last?.absoluteStep else {
            return .emptyNoteGrid(lengthSteps: resolvedLength)
        }

        let windowStartAbsoluteStep = lastAbsoluteStep - snapshot.maxSteps + 1
        let stepsBySnapshotOffset = Dictionary(
            uniqueKeysWithValues: snapshot.steps.map { step in
                (step.absoluteStep - windowStartAbsoluteStep, step.clipStep)
            }
        )
        let materializedSteps = (0..<resolvedLength).map { offset in
            stepsBySnapshotOffset[boundedStart + offset] ?? .empty
        }

        return .noteGrid(lengthSteps: resolvedLength, steps: materializedSteps)
    }

    private static func resolvedLengthSteps(_ lengthSteps: Int, maxSteps: Int) -> Int {
        min(max(1, lengthSteps), max(1, maxSteps))
    }

    private static func resolvedStartStep(_ startStep: Int, lengthSteps: Int, maxSteps: Int) -> Int {
        min(max(0, startStep), max(0, max(1, maxSteps) - lengthSteps))
    }
}

private extension CaptureSnapshot.Step {
    var clipStep: ClipStep {
        guard !notes.isEmpty else {
            return .empty
        }

        return ClipStep(
            main: ClipLane(chance: 1, notes: notes.map(\.clipStepNote)),
            fill: nil
        )
    }
}

private extension CaptureSnapshot.Note {
    var clipStepNote: ClipStepNote {
        ClipStepNote(
            pitch: pitch,
            velocity: velocity,
            lengthSteps: lengthSteps
        ).normalized
    }
}
