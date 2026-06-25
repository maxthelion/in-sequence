import AVFoundation
import Foundation

/// Deterministic, programmatic fixture builder that constructs a `Project`
/// exercising every *sounding* destination kind plus the send/mixer-bus
/// routing topology, for a real-audio test pass.
///
/// Sound sources used (no AIR Music Technology AUs — expired licenses):
///   * Mono melodic track → Arturia Analog Lab V (AU instrument, aumu/Alav/Artu)
///   * Slice track        → generated sine-burst WAV (no external-file dependency)
///   * Drum kit group     → per-part generated one-shot WAVs played by the
///                          built-in `SamplePlaybackEngine` via `.sample(...)`.
///
/// Why `.sample` for the drums (not `.internalSampler(.drumKitDefault)`): the
/// internal-sampler destination is NOT implemented as a sound source. In
/// `EngineController` and every dispatch switch it falls into
/// `case .internalSampler, ...: break`, so a drum kit on the internal sampler
/// is silent. Only `.auInstrument`/`.midi` (AudioInstrumentHost) and
/// `.sample`/`.slicer` (SamplePlaybackEngine) actually render audio. Routing
/// the drum parts through `.sample` puts them on the working render path.
///
/// The builder is pure/deterministic: it uses fixed UUIDs everywhere so the
/// resulting document round-trips. The only side effect is
/// `materializeAllSamples(...)`, which writes every generated WAV (the four
/// drum hits + the slicer loop) into the AudioSampleLibrary tree so the
/// sample/slicer destinations resolve at runtime; it is NOT called by
/// `makeProject()`.
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

    /// Library-relative path for the generated melodic-lead tone sample used by
    /// the SAMPLE-ONLY fixture variant (replaces the Analog Lab AU track). Lives
    /// under `breaks/` so it resolves to a non-drum category.
    static let melodicSampleRelativePath = "breaks/audio-rich-fixture-lead.wav"

    /// Stable UUIDv5 ID the AudioSampleLibrary scan will mint for the generated
    /// melodic-lead file.
    static var melodicSampleID: UUID {
        AudioSampleLibrary.stableID(forRelativePath: melodicSampleRelativePath)
    }

    static let melodicSampleRate: Double = 44_100
    static let melodicLengthFrames: Int64 = 22_050 // ~0.5s @ 44.1kHz

    /// Library-relative path for the generated CONTINUOUSLY-SUSTAINING drone
    /// tone used by the SAMPLE-ONLY fixture. Unlike the lead/drum one-shots
    /// (which fire on sparse steps and decay), this sample is long and holds a
    /// constant amplitude, so a track that triggers it on EVERY step always has
    /// audio on the master path. That makes routing-stress's `masterPeak`
    /// SILENCE metric meaningful: it flags a track that WAS sounding going
    /// silent on a routing op, not the legitimate gaps between sparse one-shots.
    static let droneSampleRelativePath = "breaks/audio-rich-fixture-drone.wav"

    /// Stable UUIDv5 ID the AudioSampleLibrary scan will mint for the drone file.
    static var droneSampleID: UUID {
        AudioSampleLibrary.stableID(forRelativePath: droneSampleRelativePath)
    }

    static let droneSampleRate: Double = 44_100
    static let droneLengthFrames: Int64 = 176_400 // ~4.0s @ 44.1kHz (bridges steps)

    /// Library-relative path for the SMOOTH drone used by the DRUM-FREE
    /// routing-stress click fixture. Unlike the every-step drone above (whose
    /// per-step retrigger onsets spike the discontinuity metric to ~0.5 and make
    /// a clean baseline impossible), this is a LONG (30s) sample with a slow
    /// 50ms attack/release that is triggered ONCE — a single continuous voice,
    /// no retrigger transients — so the master maxSampleDelta stays near zero and
    /// the absolute CLICK floor genuinely bites.
    static let smoothDroneSampleRelativePath = "breaks/audio-rich-fixture-smooth-drone.wav"

    static var smoothDroneSampleID: UUID {
        AudioSampleLibrary.stableID(forRelativePath: smoothDroneSampleRelativePath)
    }

    static let smoothDroneLengthFrames: Int64 = 1_323_000 // 30s @ 44.1kHz (spans a whole run)

    /// A synthesized drum one-shot: which part it is, the relative library path
    /// the WAV is written to, and how long it runs. Each lives under the part's
    /// own category dir (e.g. `kick/`, `snare/`, `hatClosed/`, `clap/`) so the
    /// library scan files them as drum voices.
    struct DrumHit {
        let tag: String
        let trackName: String
        let category: AudioSampleCategory
        let relativePath: String
        let lengthFrames: Int64

        var sampleID: UUID {
            AudioSampleLibrary.stableID(forRelativePath: relativePath)
        }

        func makeSample() -> AudioSample {
            AudioSample(
                id: sampleID,
                name: trackName,
                fileRef: .appSupportLibrary(relativePath: relativePath),
                category: category,
                lengthSeconds: Double(lengthFrames) / AudioRichFixture.drumSampleRate,
                lengthFrames: lengthFrames,
                sampleRate: AudioRichFixture.drumSampleRate
            )
        }
    }

    static let drumSampleRate: Double = 44_100

    /// The four drum parts, each backed by a distinct synthesized one-shot.
    /// Lengths are all <= ~0.4s @ 44.1kHz, mono.
    static let drumHits: [DrumHit] = [
        DrumHit(
            tag: "kick",
            trackName: "Kick",
            category: .kick,
            relativePath: "kick/audio-rich-kick.wav",
            lengthFrames: 13_230 // ~0.30s
        ),
        DrumHit(
            tag: "snare",
            trackName: "Snare",
            category: .snare,
            relativePath: "snare/audio-rich-snare.wav",
            lengthFrames: 8_820 // ~0.20s
        ),
        DrumHit(
            tag: "hat-closed",
            trackName: "Hat",
            category: .hatClosed,
            relativePath: "hatClosed/audio-rich-hat.wav",
            lengthFrames: 3_528 // ~0.08s
        ),
        DrumHit(
            tag: "clap",
            trackName: "Clap",
            category: .clap,
            relativePath: "clap/audio-rich-clap.wav",
            lengthFrames: 7_056 // ~0.16s
        ),
    ]

    private static func id(_ suffix: String) -> UUID {
        // Last UUID group is 12 hex chars; `suffix` supplies the final 4.
        UUID(uuidString: "0000A0D1-0000-4000-8000-00000000\(suffix)")!
    }

    // MARK: - Build

    /// Builds the representative project by calling the app's own mutating
    /// helpers so the result is internally valid and normalized.
    static func makeProject() -> Project {
        // An empty library so `addDrumGroup` falls back to the Apple internal
        // sampler for every part; we then re-point each part at a generated
        // `.sample(...)` below so the kit is actually audible.
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

        // 3. Drum kit group → each part on a generated `.sample(...)` one-shot
        //    (the working render path; the internal sampler is silent).
        let drumPlan = DrumGroupPlan(
            name: "Audio Rich Kit",
            color: "#8AA",
            members: drumHits.map { hit in
                DrumGroupPlan.Member(
                    tag: hit.tag,
                    trackName: hit.trackName,
                    routesToShared: false
                )
            },
            templateID: nil,
            sharedDestination: nil,
            // Keep parts on master so we don't auto-mint a per-kit bus; we add
            // our own mixer bus explicitly below.
            busRouting: .master
        )
        project.addDrumGroup(plan: drumPlan, library: emptyLibrary)

        // Re-point each member at its generated sample (in plan/member order) so
        // the kit renders. addDrumGroup appends one member track per plan member
        // in order, so the last group's memberIDs line up with `drumHits`.
        let drumGroup = project.trackGroups.last
        let memberIDs = drumGroup?.memberIDs ?? []
        for (offset, memberID) in memberIDs.enumerated() where offset < drumHits.count {
            let hit = drumHits[offset]
            let drumSample = hit.makeSample()
            if let index = project.tracks.firstIndex(where: { $0.id == memberID }) {
                project.tracks[index].destination = .sample(
                    sampleID: hit.sampleID,
                    settings: .default
                )
            }
            project.addToAssetPool(
                kind: .sample,
                assetID: drumSample.id,
                addedAt: Date(timeIntervalSince1970: 0)
            )
        }
        // Arm a basic four-on-the-floor on the kick so the kit makes sound.
        if let kickID = memberIDs.first,
           let index = project.tracks.firstIndex(where: { $0.id == kickID }) {
            project.tracks[index].stepPattern = Self.everyNthStep(every: 4)
        }

        // 4. Routing for the real-audio pass.
        //    a. One explicit mixer bus.
        let busID = project.addMixerBus(name: "FX Bus", color: "#3A7")
        //    b. Route the drum kick to the mixer bus so the bus path is live.
        if let kickID = memberIDs.first {
            project.setTrackOutputBus(trackID: kickID, busID: busID)
        }
        //    c. Send A and Send B each get one native filter insert.
        project.setSendBusInserts([Self.fixedFilterInsert(idSuffix: "0A01")], id: .sendA)
        project.setSendBusInserts([Self.fixedFilterInsert(idSuffix: "0B01")], id: .sendB)

        // Select the mono track as the focused track for a tidy load.
        project.selectedTrackID = monoTrackID
        return project
    }

    /// SAMPLE-ONLY variant of `makeProject()` for UNATTENDED automation: identical
    /// drum group (.sample hits) + slice track, but the Analog Lab AU mono track is
    /// REPLACED with a `.monoMelodic` track on a generated `.sample(...)` tone. There
    /// is NO `.auInstrument` destination anywhere, so a headless/wired launch sounds
    /// deterministically without ever triggering the macOS AU permission modal.
    ///
    /// Pure/deterministic (fixed UUIDs). Call `materializeAllSamples(...)` (or launch
    /// with `SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES=1`) so the `.sample`/`.slicer`
    /// destinations resolve at runtime.
    static func makeSampleOnlyProject() -> Project {
        let emptyLibrary = AudioSampleLibrary(libraryRoot: URL(fileURLWithPath: "/nonexistent-audio-rich-fixture"))

        var project = Project.empty

        // 1. Mono melodic track driven by a generated `.sample(...)` tone
        //    (NO AU instrument — the working render path, prompt-free).
        project.appendTrack(trackType: .monoMelodic)
        let monoTrackID = project.selectedTrackID
        let leadSample = makeMelodicSample()
        if let index = project.tracks.firstIndex(where: { $0.id == monoTrackID }) {
            project.tracks[index].name = "Sample Lead"
            project.tracks[index].destination = .sample(
                sampleID: melodicSampleID,
                settings: .default
            )
            // Drive the send path: route this track's audio to Send A.
            project.tracks[index].mix.sendA = 0.6
            // Give it a simple ascending arpeggio so it makes sound.
            project.tracks[index].pitches = [60, 63, 67, 70]
            project.tracks[index].stepPattern = Self.everyNthStep(every: 4)
        }
        project.addToAssetPool(
            kind: .sample,
            assetID: leadSample.id,
            addedAt: Date(timeIntervalSince1970: 0)
        )

        // 2. Slice track from a generated sample (identical to makeProject()).
        let sample = makeSlicerSample()
        let sliceTrackID = project.appendSliceTrack(sample: sample)
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
            project.tracks[index].mix.sendB = 0.5
        }
        project.addToAssetPool(
            kind: .sample,
            assetID: sample.id,
            addedAt: Date(timeIntervalSince1970: 0)
        )

        // 3. Drum kit group → each part on a generated `.sample(...)` one-shot.
        let drumPlan = DrumGroupPlan(
            name: "Audio Rich Kit",
            color: "#8AA",
            members: drumHits.map { hit in
                DrumGroupPlan.Member(
                    tag: hit.tag,
                    trackName: hit.trackName,
                    routesToShared: false
                )
            },
            templateID: nil,
            sharedDestination: nil,
            busRouting: .master
        )
        project.addDrumGroup(plan: drumPlan, library: emptyLibrary)

        let drumGroup = project.trackGroups.last
        let memberIDs = drumGroup?.memberIDs ?? []
        for (offset, memberID) in memberIDs.enumerated() where offset < drumHits.count {
            let hit = drumHits[offset]
            let drumSample = hit.makeSample()
            if let index = project.tracks.firstIndex(where: { $0.id == memberID }) {
                project.tracks[index].destination = .sample(
                    sampleID: hit.sampleID,
                    settings: .default
                )
            }
            project.addToAssetPool(
                kind: .sample,
                assetID: drumSample.id,
                addedAt: Date(timeIntervalSince1970: 0)
            )
        }
        if let kickID = memberIDs.first,
           let index = project.tracks.firstIndex(where: { $0.id == kickID }) {
            project.tracks[index].stepPattern = Self.everyNthStep(every: 4)
        }

        // 4. Routing (identical to makeProject()).
        let busID = project.addMixerBus(name: "FX Bus", color: "#3A7")
        if let kickID = memberIDs.first {
            project.setTrackOutputBus(trackID: kickID, busID: busID)
        }
        project.setSendBusInserts([Self.fixedFilterInsert(idSuffix: "0A01")], id: .sendA)
        project.setSendBusInserts([Self.fixedFilterInsert(idSuffix: "0B01")], id: .sendB)

        // 5. CONTINUOUSLY-SUSTAINING drone track (LAST, so the index-based
        //    routing-stress ops never touch it: it stays on master and keeps
        //    sounding throughout the whole sequence). It drives a long, flat-
        //    amplitude sample retriggered on EVERY step, so the master path is
        //    never silent between the other tracks' sparse one-shots. This makes
        //    the rig's SILENCE metric honest: -inf masterPeak now means a real
        //    routing failure, not a gap between pattern hits.
        project.appendTrack(trackType: .monoMelodic)
        let droneTrackID = project.selectedTrackID
        let droneSample = makeDroneSample()
        if let index = project.tracks.firstIndex(where: { $0.id == droneTrackID }) {
            project.tracks[index].name = "Sustain Drone"
            project.tracks[index].destination = .sample(
                sampleID: droneSampleID,
                settings: .default
            )
            // Trigger on every step so overlapping retriggers keep the master
            // path continuously sounding; routed to master (no sends).
            project.tracks[index].pitches = [48]
            project.tracks[index].stepPattern = Array(repeating: true, count: 16)
        }
        project.addToAssetPool(
            kind: .sample,
            assetID: droneSample.id,
            addedAt: Date(timeIntervalSince1970: 0)
        )

        project.selectedTrackID = monoTrackID
        return project
    }

    // MARK: - Slicer sample (generated, not file-dependent for build)

    /// The `AudioSample` metadata describing the generated slicer WAV. The
    /// `fileRef` points at the AudioSampleLibrary tree; `materializeAllSamples`
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

    /// The `AudioSample` metadata describing the generated melodic-lead WAV used
    /// by the SAMPLE-ONLY fixture variant. `materializeAllSamples` writes the bytes.
    static func makeMelodicSample() -> AudioSample {
        AudioSample(
            id: melodicSampleID,
            name: "Audio Rich Fixture Lead",
            fileRef: .appSupportLibrary(relativePath: melodicSampleRelativePath),
            category: AudioSampleCategory(rawValue: "breaks") ?? .breaks,
            lengthSeconds: Double(melodicLengthFrames) / melodicSampleRate,
            lengthFrames: melodicLengthFrames,
            sampleRate: melodicSampleRate
        )
    }

    /// The `AudioSample` metadata for the long, flat-amplitude drone WAV that
    /// gives the sample-only fixture a continuously-sounding source.
    static func makeDroneSample() -> AudioSample {
        AudioSample(
            id: droneSampleID,
            name: "Audio Rich Fixture Drone",
            fileRef: .appSupportLibrary(relativePath: droneSampleRelativePath),
            category: AudioSampleCategory(rawValue: "breaks") ?? .breaks,
            lengthSeconds: Double(droneLengthFrames) / droneSampleRate,
            lengthFrames: droneLengthFrames,
            sampleRate: droneSampleRate
        )
    }

    // MARK: - Materialization (real-audio pass only; not called by makeProject)

    /// Writes ALL generated WAVs — the four drum one-shots and the slicer loop —
    /// into the AudioSampleLibrary tree so every `.sample(...)` / `.slicer(...)`
    /// destination in `makeProject()` resolves at runtime.
    ///
    /// Call this from the real-audio harness before loading the document;
    /// `makeProject()` does not invoke it (keeps the builder pure).
    static func materializeAllSamples(
        libraryRoot: URL = AudioSampleLibrary.shared.libraryRoot
    ) throws {
        try materializeSlicerSample(libraryRoot: libraryRoot)
        try materializeMelodicSample(libraryRoot: libraryRoot)
        try materializeDroneSample(libraryRoot: libraryRoot)
        try materializeSmoothDroneSample(libraryRoot: libraryRoot)
        for hit in drumHits {
            try materializeDrumHit(hit, libraryRoot: libraryRoot)
        }
    }

    /// The `AudioSample` metadata for the smooth drum-free-fixture drone.
    static func makeSmoothDroneSample() -> AudioSample {
        AudioSample(
            id: smoothDroneSampleID,
            name: "Audio Rich Fixture Smooth Drone",
            fileRef: .appSupportLibrary(relativePath: smoothDroneSampleRelativePath),
            category: AudioSampleCategory(rawValue: "breaks") ?? .breaks,
            lengthSeconds: Double(smoothDroneLengthFrames) / droneSampleRate,
            lengthFrames: smoothDroneLengthFrames,
            sampleRate: droneSampleRate
        )
    }

    /// Synthesizes a long (30s) CONSTANT-amplitude drone with a slow 50ms
    /// attack and 50ms release, triggered ONCE by the drum-free click fixture.
    /// A single continuous voice (no per-step retrigger) keeps the master
    /// maxSampleDelta near zero, so the routing-stress CLICK floor actually bites.
    @discardableResult
    static func materializeSmoothDroneSample(
        libraryRoot: URL = AudioSampleLibrary.shared.libraryRoot
    ) throws -> URL {
        let total = Double(smoothDroneLengthFrames)
        return try writeMonoWAV(
            relativePath: smoothDroneSampleRelativePath,
            libraryRoot: libraryRoot,
            sampleRate: droneSampleRate,
            frameCount: Int(smoothDroneLengthFrames)
        ) { frame, _ in
            let t = Double(frame) / droneSampleRate
            let f0 = 130.81 // C3
            let fundamental = sin(2.0 * Double.pi * f0 * t)
            let fifth = 0.4 * sin(2.0 * Double.pi * f0 * 1.5 * t)
            let octave = 0.3 * sin(2.0 * Double.pi * f0 * 2.0 * t)
            let secondsRemaining = (total - Double(frame)) / droneSampleRate
            // Slow 50ms attack + 50ms release; flat in between (no retrigger).
            let attack = min(1.0, t / 0.05)
            let release = min(1.0, max(0.0, secondsRemaining / 0.05))
            return Float((fundamental + fifth + octave) * attack * release * 0.3)
        }
    }

    /// Synthesizes a ~0.5s mono sustained-tone WAV (a few harmonics, gentle
    /// decay) and writes it into the AudioSampleLibrary tree so the SAMPLE-ONLY
    /// fixture's melodic lead resolves at runtime. Returns the written URL.
    @discardableResult
    static func materializeMelodicSample(
        libraryRoot: URL = AudioSampleLibrary.shared.libraryRoot
    ) throws -> URL {
        try writeMonoWAV(
            relativePath: melodicSampleRelativePath,
            libraryRoot: libraryRoot,
            sampleRate: melodicSampleRate,
            frameCount: Int(melodicLengthFrames)
        ) { frame, _ in
            let t = Double(frame) / melodicSampleRate
            // Root ~261.63 Hz (C4) with octave + fifth harmonics for a richer tone.
            let f0 = 261.63
            let fundamental = sin(2.0 * Double.pi * f0 * t)
            let octave = 0.4 * sin(2.0 * Double.pi * f0 * 2.0 * t)
            let fifth = 0.25 * sin(2.0 * Double.pi * f0 * 1.5 * t)
            // Short attack, long decay over the half-second.
            let attack = min(1.0, t / 0.005)
            let decay = exp(-t / 0.35)
            return Float((fundamental + octave + fifth) * attack * decay * 0.5)
        }
    }

    /// Synthesizes a ~4s mono drone tone WAV at a CONSTANT amplitude (no decay)
    /// and writes it into the AudioSampleLibrary tree. A track triggering this on
    /// every step keeps the master path continuously sounding, so routing-stress
    /// can tell a real routing silence apart from the gaps between sparse
    /// one-shots. Returns the written URL.
    @discardableResult
    static func materializeDroneSample(
        libraryRoot: URL = AudioSampleLibrary.shared.libraryRoot
    ) throws -> URL {
        try writeMonoWAV(
            relativePath: droneSampleRelativePath,
            libraryRoot: libraryRoot,
            sampleRate: droneSampleRate,
            frameCount: Int(droneLengthFrames)
        ) { frame, _ in
            let t = Double(frame) / droneSampleRate
            // Low sustained tone ~130.81 Hz (C3) with a fifth + octave for body.
            let f0 = 130.81
            let fundamental = sin(2.0 * Double.pi * f0 * t)
            let fifth = 0.4 * sin(2.0 * Double.pi * f0 * 1.5 * t)
            let octave = 0.3 * sin(2.0 * Double.pi * f0 * 2.0 * t)
            // Tiny attack to avoid a click; then FLAT — no decay — so the level
            // stays up for the whole sample regardless of where a step lands.
            let attack = min(1.0, t / 0.005)
            return Float((fundamental + fifth + octave) * attack * 0.3)
        }
    }

    /// Synthesizes a ~2s mono sine-burst loop (8 descending-pitch bursts) and
    /// writes it as a WAV into the AudioSampleLibrary tree so the slicer can
    /// resolve `slicerSampleRelativePath` at runtime. Returns the written URL.
    @discardableResult
    static func materializeSlicerSample(
        libraryRoot: URL = AudioSampleLibrary.shared.libraryRoot
    ) throws -> URL {
        try writeMonoWAV(
            relativePath: slicerSampleRelativePath,
            libraryRoot: libraryRoot,
            sampleRate: slicerSampleRate,
            frameCount: Int(slicerLengthFrames)
        ) { frame, _ in
            let burstFrames = Int(slicerLengthFrames) / 8
            let baseFreqs: [Double] = [440, 392, 349.23, 329.63, 293.66, 261.63, 246.94, 220]
            let burst = min(frame / max(burstFrames, 1), baseFreqs.count - 1)
            let freq = baseFreqs[burst]
            let localFrame = frame - burst * burstFrames
            // Short exponential decay envelope per burst so slices are distinct.
            let env = exp(-Double(localFrame) / (Double(burstFrames) * 0.35))
            let theta = 2.0 * Double.pi * freq * Double(frame) / slicerSampleRate
            return Float(sin(theta) * env * 0.7)
        }
    }

    /// Synthesizes the one-shot WAV for a drum part and writes it into the
    /// AudioSampleLibrary tree. Returns the written URL.
    @discardableResult
    static func materializeDrumHit(
        _ hit: DrumHit,
        libraryRoot: URL = AudioSampleLibrary.shared.libraryRoot
    ) throws -> URL {
        let frames = Int(hit.lengthFrames)
        let sr = drumSampleRate
        return try writeMonoWAV(
            relativePath: hit.relativePath,
            libraryRoot: libraryRoot,
            sampleRate: sr,
            frameCount: frames
        ) { frame, rng in
            drumSampleValue(tag: hit.tag, frame: frame, frameCount: frames, sampleRate: sr, rng: &rng)
        }
    }

    /// Returns the float sample value at `frame` for the given drum tag.
    ///
    /// Synthesis recipes (all short, mono, 44.1k):
    ///   * kick  — low sine (~110→45 Hz) with a fast pitch drop + exp decay,
    ///             plus a brief click transient.
    ///   * snare — white-noise burst + a 180 Hz body tone, exp decay.
    ///   * hat   — high-passed (differentiated) white noise, very fast decay.
    ///   * clap  — three short noise bursts in quick succession (the classic
    ///             clap "flam"), each exp-decayed.
    private static func drumSampleValue(
        tag: String,
        frame: Int,
        frameCount: Int,
        sampleRate sr: Double,
        rng: inout DeterministicRNG
    ) -> Float {
        let t = Double(frame) / sr
        switch tag {
        case "kick":
            // Pitch sweeps from ~110 Hz down to ~45 Hz over the first ~40ms.
            let f0 = 110.0, f1 = 45.0
            let sweep = exp(-t / 0.03)
            let freq = f1 + (f0 - f1) * sweep
            let phase = 2.0 * Double.pi * freq * t
            let env = exp(-t / 0.10)
            let click = frame < Int(0.002 * sr) ? (rng.nextUnit() * 0.4) : 0
            return Float((sin(phase) * env + click) * 0.9)

        case "snare":
            let noise = rng.nextUnit()
            let tone = sin(2.0 * Double.pi * 180.0 * t)
            let env = exp(-t / 0.06)
            return Float((noise * 0.7 + tone * 0.3) * env * 0.8)

        case "hat-closed", "hat":
            // Crude high-pass: first difference of white noise emphasises highs.
            let prev = rng.lastUnit
            let noise = rng.nextUnit()
            let hp = noise - prev
            let env = exp(-t / 0.02)
            return Float(hp * env * 0.6)

        case "clap":
            // Three noise bursts at 0ms, ~10ms, ~20ms, each fast-decayed.
            let burstStarts = [0.0, 0.010, 0.020]
            var value = 0.0
            for start in burstStarts where t >= start {
                let local = t - start
                let env = exp(-local / 0.012)
                value += rng.nextUnit() * env
            }
            // Short decaying tail after the bursts.
            let tail = exp(-t / 0.05)
            return Float((value * 0.5) * tail * 0.9)

        default:
            return 0
        }
    }

    // MARK: - WAV writer

    /// Generates a mono float32 WAV at `relativePath` under `libraryRoot`,
    /// sourcing each frame from `sampleAt(frameIndex, &rng)`. The RNG is
    /// deterministically seeded from the relative path so repeated runs produce
    /// byte-identical noise.
    @discardableResult
    private static func writeMonoWAV(
        relativePath: String,
        libraryRoot: URL,
        sampleRate: Double,
        frameCount: Int,
        sampleAt: (_ frame: Int, _ rng: inout DeterministicRNG) -> Float
    ) throws -> URL {
        let url = libraryRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "AudioRichFixture", code: 1)
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw NSError(domain: "AudioRichFixture", code: 2)
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let channel = buffer.floatChannelData?[0] else {
            throw NSError(domain: "AudioRichFixture", code: 3)
        }

        var rng = DeterministicRNG(seed: relativePath)
        for frame in 0..<frameCount {
            channel[frame] = sampleAt(frame, &rng)
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

/// Small deterministic LCG producing reproducible white noise in [-1, 1].
/// Seeded from a string so each generated WAV is byte-identical across runs.
struct DeterministicRNG {
    private var state: UInt64
    private(set) var lastUnit: Double = 0

    init(seed: String) {
        // FNV-1a 64-bit hash of the seed string for a stable starting state.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        state = hash == 0 ? 0x9E37_79B9_7F4A_7C15 : hash
    }

    /// Returns a deterministic pseudo-random value in [-1, 1].
    mutating func nextUnit() -> Double {
        // SplitMix64 step.
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        let unit = Double(z >> 11) / Double(1 << 53) // [0, 1)
        let signed = unit * 2.0 - 1.0
        lastUnit = signed
        return signed
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
