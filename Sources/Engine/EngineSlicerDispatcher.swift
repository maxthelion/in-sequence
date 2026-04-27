import Foundation

enum EngineSlicerDispatcher {
    static func enqueueSliceTriggers(
        for events: [NoteEvent],
        trackID: UUID,
        sliceSetID: UUID,
        settings: SlicerSettings,
        snapshot: PlaybackSnapshot,
        sampleLibrary: AudioSampleLibrary,
        sampleLibraryRoot: URL,
        stepsPerBar: Int,
        bpm: Double,
        now: TimeInterval,
        eventQueue: EventQueue
    ) {
        guard let sliceSet = snapshot.sliceSet(id: sliceSetID),
              let sampleID = sliceSet.sampleID,
              let sample = sampleLibrary.sample(id: sampleID),
              let url = try? sample.fileRef.resolve(libraryRoot: sampleLibraryRoot)
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
            let wholeEndFrame = sliceSet.markers.first?.endFrame ?? marker.endFrame
            let microOffset = Int64(marker.microTimingSteps * Double(framesPerStep))
            let startFrame = max(0, marker.startFrame + microOffset)
            let endFrame = resolution.runFromHere ? wholeEndFrame : marker.endFrame
            guard endFrame > startFrame else {
                continue
            }
            let effectiveSettings = SlicerSettings(
                gain: settings.gain + marker.gain,
                transpose: settings.transpose,
                voiceMode: settings.voiceMode
            ).clamped

            eventQueue.enqueue(ScheduledEvent(
                scheduledHostTime: now,
                payload: .sliceTrigger(
                    trackID: trackID,
                    sampleURL: url,
                    startFrame: startFrame,
                    endFrame: endFrame,
                    settings: effectiveSettings,
                    reverse: marker.reverse,
                    scheduledHostTime: now
                )
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
