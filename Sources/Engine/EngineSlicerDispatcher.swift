import Foundation

enum EngineSlicerDispatcher {
    static func enqueueSliceTriggers(
        for events: [NoteEvent],
        trackID: UUID,
        sliceSetID: UUID,
        settings: SlicerSettings,
        snapshot: PlaybackSnapshot,
        sampleLibrary: AudioSampleLibrary,
        stepsPerBar: Int,
        bpm: Double,
        scheduledHostTime: TimeInterval,
        eventQueue: EventQueue,
        repeatOwnerTrackID: UUID? = nil
    ) {
        guard let sliceSet = snapshot.sliceSet(id: sliceSetID),
              let sampleID = sliceSet.sampleID,
              let sample = sampleLibrary.sample(id: sampleID)
        else {
            return
        }

        let secondsPerStep = (60 / max(1, bpm)) * (4 / Double(max(1, stepsPerBar)))
        let sampleRate = sample.sampleRate ?? 44_100
        let framesPerStep = Int64(secondsPerStep * sampleRate)

        for event in events {
            let resolution = sliceResolution(for: event.voiceTag, in: sliceSet)
            guard let marker = sliceSet.marker(at: resolution.index) else {
                continue
            }
            let stepParameters = (event.sliceParameters ?? .default).clamped
            let wholeEndFrame = sliceSet.markers.first?.endFrame ?? marker.endFrame
            let baseEndFrame = resolution.runFromHere ? wholeEndFrame : marker.endFrame
            let baseLength = max(1, baseEndFrame - marker.startFrame)
            let startTrimFrames = Int64((Double(baseLength) * stepParameters.startTrim).rounded())
            let endTrimFrames = Int64((Double(baseLength) * stepParameters.endTrim).rounded())
            let microOffset = Int64(marker.microTimingSteps * Double(framesPerStep))
            let startFrame = max(0, marker.startFrame + startTrimFrames + microOffset)
            let endFrame = max(startFrame + 1, baseEndFrame - endTrimFrames)
            guard endFrame > startFrame else {
                continue
            }
            let effectiveSettings = SlicerSettings(
                gain: settings.gain + marker.gain + stepParameters.gain,
                transpose: settings.transpose + Int(stepParameters.pitch.rounded()),
                voiceMode: stepParameters.choke ? .mono : .polyphonic
            ).clamped

            eventQueue.enqueue(ScheduledEvent(
                scheduledHostTime: scheduledHostTime,
                payload: .sliceTrigger(
                    trackID: trackID,
                    sampleID: sampleID,
                    startFrame: startFrame,
                    endFrame: endFrame,
                    settings: effectiveSettings,
                    reverse: marker.reverse || stepParameters.reverse,
                    stepParameters: stepParameters,
                    scheduledHostTime: scheduledHostTime
                ),
                repeatOwnerTrackID: repeatOwnerTrackID
            ))
        }
    }

    static func sliceResolution(for voiceTag: String?, in sliceSet: SliceSet) -> (index: Int, runFromHere: Bool) {
        guard let rawTag = voiceTag?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTag.isEmpty
        else {
            return (0, false)
        }

        if rawTag.hasPrefix("slice-run-"),
           let index = Int(rawTag.dropFirst("slice-run-".count))
        {
            return (min(max(index, 0), max(0, sliceSet.markers.count - 1)), true)
        }

        if rawTag.hasPrefix("slice-"),
           let index = Int(rawTag.dropFirst("slice-".count))
        {
            return (min(max(index, 0), max(0, sliceSet.markers.count - 1)), false)
        }

        if let index = sliceSet.markers.firstIndex(where: { $0.tag == rawTag }) {
            return (index, false)
        }

        return (0, false)
    }
}
