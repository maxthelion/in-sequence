import AVFoundation
import Foundation

/// Deterministic, programmatic fixture builder that constructs a `Project`
/// exercising every sound-producing destination kind plus the send/mixer-bus
/// routing topology, for a real-audio test pass.
///
/// Sound sources used (no AIR Music Technology AUs — expired licenses):
///   * Mono melodic track → Arturia Analog Lab V (AU instrument, aumu/Alav/Artu)
///   * Slice track        → generated sine-burst WAV (no external-file dependency)
///   * Drum kit group     → Apple internal sampler (`.drumKitDefault`) per part
///
/// The builder is pure/deterministic: it uses fixed UUIDs everywhere so the
/// resulting document round-trips byte-for-byte. The only side effect is
/// `materializeSlicerSample(...)`, which writes the generated WAV into the
/// AudioSampleLibrary tree so the slicer can resolve it at runtime; it is NOT
/// called by `makeProject()`.
enum AudioRichFixture {
    // MARK: - Fixed identifiers (deterministic round-trip)

    /// Arturia Analog Lab V — music-device AU. The app matches AUs purely by
    /// four-char type/subtype/manufacturer (see AUAudioUnitFactory.instantiate /
    /// AudioInstrumentChoice.fourCharCodeValue); the `version` field is NOT used
    /// for lookup, so it is set to 0.
    static let analogLabComponentID = AudioComponentID(
        type: "aumu",
        subtype: "Alav",
        manufacturer: "Artu",
        version: 0
    )

    /// Library-relative path for the generated slicer sample. Lives under a
    /// `breaks` category dir so `AudioSampleCategory(rawValue:)` resolves it to
    /// a real (non-drum) category and the slicer treats it as a loopable break.
    static let slicerSampleRelativePath = "breaks/audio-rich-fixture-loop.wav"

    /// Stable UUIDv5 ID the AudioSampleLibrary scan will mint for the generated
    /// file. Derived via the same derivation the library uses, so the sample ID
    /// stored in the document matches what the live library assigns on scan.
    static var slicerSampleID: UUID {
        AudioSampleLibrary.stableID(forRelativePath: slicerSampleRelativePath)
    }

    static let slicerSampleRate: Double = 44_100
    static let slicerLengthFrames: Int64 = 88_200 // ~2.0s @ 44.1kHz

    private static func id(_ suffix: String) -> UUID {
        // Last UUID group is 12 hex chars; `suffix` supplies the final 4.
        UUID(uuidString: "0000A0D1-0000-4000-8000-00000000\(suffix)")!
    }

    // MARK: - Build

    /// Builds the representative project by calling the app's own mutating
    /// helpers so the result is internally valid and normalized.
    static func makeProject() -> Project {
        // An empty library so `addDrumGroup` falls back to the Apple internal
        // sampler for every part (no third-party AU, deterministic regardless
        // of what's installed on the machine).
        let emptyLibrary = AudioSampleLibrary(libraryRoot: URL(fileURLWithPath: "/nonexistent-audio-rich-fixture"))

        var project = Project.empty

        // 1. Mono melodic track driven by Arturia Analog Lab V (AU instrument).
        project.appendTrack(trackType: .monoMelodic)
        let monoTrackID = project.selectedTrackID
        if let index = project.tracks.firstIndex(where: { $0.id == monoTrackID }) {
            project.tracks[index].name = "Analog Lab Lead"
            project.tracks[index].destination = .auInstrument(
                componentID: analogLabComponentID,
                stateBlob: nil
            )
            // Drive the send path: route this track's audio to Send A.
            project.tracks[index].mix.sendA = 0.6
            // Give it a simple ascending arpeggio so it makes sound.
            project.tracks[index].pitches = [60, 63, 67, 70]
            project.tracks[index].stepPattern = Self.everyNthStep(every: 4)
        }

        // 2. Slice track from a generated sample.
        let sample = makeSlicerSample()
        let sliceTrackID = project.appendSliceTrack(sample: sample)
        // appendSliceTrack seeds a single whole-sample marker; add interior
        // slice markers so there is something to trigger, and arm a few steps.
        if let sliceSetID = project.sliceSetID(forTrack: sliceTrackID) {
            project.updateSliceSet(id: sliceSetID) { set in
                let frames = Self.slicerLengthFrames
                let count: Int64 = 8
                var markers = [set.markers.first].compactMap { $0 } // whole-sample
                for i in 0..<count {
                    let start = frames * i / count
                    let end = frames * (i + 1) / count
                    markers.append(SliceMarker(startFrame: start, endFrame: end))
                }
                set.markers = markers
                set.mode = .grid
                set.normalize(sampleLengthFrames: frames)
            }
        }
        if let index = project.tracks.firstIndex(where: { $0.id == sliceTrackID }) {
            project.tracks[index].stepPattern = Self.everyNthStep(every: 2)
            // Route slice audio to Send B so the second send path is exercised.
            project.tracks[index].mix.sendB = 0.5
        }
        // Pool the sample reference so the document carries it like the app does.
        project.addToAssetPool(
            kind: .sample,
            assetID: sample.id,
            addedAt: Date(timeIntervalSince1970: 0)
        )

        // 3. Drum kit group → Apple internal sampler per part (empty library
        //    forces the `.internalSampler(.drumKitDefault, ...)` fallback).
        let drumPlan = DrumGroupPlan(
            name: "Audio Rich Kit",
            color: "#8AA",
            members: [
                DrumGroupPlan.Member(tag: "kick", trackName: "Kick", routesToShared: false),
                DrumGroupPlan.Member(tag: "snare", trackName: "Snare", routesToShared: false),
                DrumGroupPlan.Member(tag: "hat-closed", trackName: "Hat", routesToShared: false),
                DrumGroupPlan.Member(tag: "clap", trackName: "Clap", routesToShared: false),
            ],
            templateID: nil,
            sharedDestination: nil,
            // Keep parts on master so we don't auto-mint a per-kit bus; we add
            // our own mixer bus explicitly below.
            busRouting: .master
        )
        project.addDrumGroup(plan: drumPlan, library: emptyLibrary)
        // Arm a basic four-on-the-floor on the kick so the kit makes sound.
        if let kickID = project.trackGroups.last?.memberIDs.first,
           let index = project.tracks.firstIndex(where: { $0.id == kickID }) {
            project.tracks[index].stepPattern = Self.everyNthStep(every: 4)
        }

        // 4. Routing for the real-audio pass.
        //    a. One explicit mixer bus.
        let busID = project.addMixerBus(name: "FX Bus", color: "#3A7")
        //    b. Route the drum kick to the mixer bus so the bus path is live.
        if let kickID = project.trackGroups.last?.memberIDs.first {
            project.setTrackOutputBus(trackID: kickID, busID: busID)
        }
        //    c. Send A and Send B each get one native filter insert.
        project.setSendBusInserts([Self.fixedFilterInsert(idSuffix: "0A01")], id: .sendA)
        project.setSendBusInserts([Self.fixedFilterInsert(idSuffix: "0B01")], id: .sendB)

        // Select the mono track as the focused track for a tidy load.
        project.selectedTrackID = monoTrackID
        return project
    }

    // MARK: - Slicer sample (generated, not file-dependent for build)

    /// The `AudioSample` metadata describing the generated slicer WAV. The
    /// `fileRef` points at the AudioSampleLibrary tree; `materializeSlicerSample`
    /// writes the actual bytes there for the real-audio pass.
    static func makeSlicerSample() -> AudioSample {
        AudioSample(
            id: slicerSampleID,
            name: "Audio Rich Fixture Loop",
            fileRef: .appSupportLibrary(relativePath: slicerSampleRelativePath),
            category: AudioSampleCategory(rawValue: "breaks") ?? .breaks,
            lengthSeconds: Double(slicerLengthFrames) / slicerSampleRate,
            lengthFrames: slicerLengthFrames,
            sampleRate: slicerSampleRate
        )
    }

    /// Synthesizes a ~2s mono sine-burst loop (8 descending-pitch bursts) and
    /// writes it as a WAV into the AudioSampleLibrary tree so the slicer can
    /// resolve `slicerSampleRelativePath` at runtime. Returns the written URL.
    ///
    /// Call this from the real-audio harness before loading the document;
    /// `makeProject()` does not invoke it (keeps the builder pure).
    @discardableResult
    static func materializeSlicerSample(
        libraryRoot: URL = AudioSampleLibrary.shared.libraryRoot
    ) throws -> URL {
        let url = libraryRoot.appendingPathComponent(slicerSampleRelativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: slicerSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "AudioRichFixture", code: 1)
        }

        let frameCount = AVAudioFrameCount(slicerLengthFrames)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "AudioRichFixture", code: 2)
        }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else {
            throw NSError(domain: "AudioRichFixture", code: 3)
        }

        let burstFrames = Int(slicerLengthFrames) / 8
        let baseFreqs: [Double] = [440, 392, 349.23, 329.63, 293.66, 261.63, 246.94, 220]
        for frame in 0..<Int(slicerLengthFrames) {
            let burst = min(frame / max(burstFrames, 1), baseFreqs.count - 1)
            let freq = baseFreqs[burst]
            let localFrame = frame - burst * burstFrames
            // Short exponential decay envelope per burst so slices are distinct.
            let env = exp(-Double(localFrame) / (Double(burstFrames) * 0.35))
            let theta = 2.0 * Double.pi * freq * Double(frame) / slicerSampleRate
            channel[frame] = Float(sin(theta) * env * 0.7)
        }

        let outFile = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try outFile.write(from: buffer)
        return url
    }

    // MARK: - Helpers

    private static func fixedFilterInsert(idSuffix: String) -> SendBusInsert {
        SendBusInsert(
            id: id(idSuffix),
            name: "Filter",
            isEnabled: true,
            wetDry: 1,
            kind: .nativeFilter(MasterFilterSettings(mode: .lowPass, cutoffHz: 8_000, resonance: 0.3))
        )
    }

    private static func everyNthStep(every n: Int, count: Int = 16) -> [Bool] {
        (0..<count).map { $0 % n == 0 }
    }
}

private extension Project {
    /// The slice-set ID currently bound to a slice track's destination, if any.
    func sliceSetID(forTrack trackID: UUID) -> UUID? {
        guard let track = tracks.first(where: { $0.id == trackID }),
              case let .slicer(sliceSetID, _) = track.destination
        else {
            return nil
        }
        return sliceSetID
    }
}
