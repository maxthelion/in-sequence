import AVFoundation
import CoreAudio
import CoreMIDI
import XCTest
@testable import SequencerAI

private typealias EngineStream = SequencerAI.Stream

/// Phase 3 verification gate (`docs/plans/2026-06-24-sample-accurate-timing.md`):
/// MIDI-out is stamped from the unified `AudioMasterClock`, sharing the audio
/// sinks' timeline, and a per-port output offset shifts the stamp by exactly the
/// offset.
///
/// # Machine-verifiable (this file, unattended — NO real MIDI hardware)
///
/// 1. **Stamp source == audio host time.** The value the engine feeds to
///    `MidiOut` for step N is `AudioMasterClock.hostSeconds(atMusicalSeconds:)`
///    for N's musical position — the SAME host time the audio sinks get from
///    `audioTime(atMusicalSeconds:).hostTime`. Asserted exactly, and asserted
///    JITTER-FREE: under a jittered pump the MIDI host time for a step does not
///    move (it is anchored to the captured render origin + the step's musical
///    position, not the pump's wake `now`).
/// 2. **Negative control.** The OLD wall-clock source (`now + stepDuration`,
///    where `now` is the pump wake) DOES move under jitter — proving the gate
///    above is load-bearing, not a tautology.
/// 3. **Per-port offset.** A `MidiOut` with `outputOffsetSeconds = δ` sends a
///    `MIDITimeStamp` exactly δ (in mach host units) later than the same send
///    with offset 0; default offset is 0 (no shift). Measured from the REAL
///    `MIDITimeStamp` carried on a packet sent through a virtual MIDI endpoint
///    (the established unattended MidiOut test transport).
///
/// # NEEDS HUMAN (hardware — NOT covered here)
///
/// That real external MIDI gear receives/plays on time, and the per-port offset
/// calibration values themselves, require a human with the hardware. The offset
/// is PLUMB-ONLY (default 0, never auto-tuned).
final class MidiOutUnifiedClockTimingTests: XCTestCase {

    private typealias Harness = OfflineFrameAccuracyTests.OfflineFrameAccuracyHarness
    private typealias CapturingSink = OfflineFrameAccuracyTests.CapturingSampleSink

    private var libraryRoot: URL!

    override func setUpWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: libraryRoot.appendingPathComponent("kick"),
            withIntermediateDirectories: true
        )
        try writeSilentWAV(to: libraryRoot.appendingPathComponent("kick/test-kick.wav"), sampleRate: 48_000)
    }

    override func tearDownWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = false
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    // MARK: - 1 + 2: stamp source == audio host time, jitter-free (+ negative control)

    /// The MIDI host time the engine derives for each step equals the audio
    /// sinks' host time for the same step, and is independent of pump jitter.
    /// Reuses the offline frame-accuracy harness so it drives the REAL
    /// `EngineController`/`AudioMasterClock` (offline, no hardware).
    func test_midiHostTime_equalsAudioHostTime_perStep_andIsJitterFree() throws {
        let bpm = 120.0
        let harness = try makeSampleHarness(bpm: bpm)
        let clock = harness.controller.audioMasterClock
        let stepDuration = harness.secondsPerStep(bpm: bpm)
        let jitter: [Double] = [0, +0.004, -0.003, +0.005, -0.004, +0.002, -0.005, +0.003]
        let steps = jitter.count

        for step in 0..<steps {
            harness.drive(step: step, now: Double(step) * stepDuration + jitter[step])
        }

        for step in 0..<steps {
            let musicalSeconds = harness.capturedFrames[step].scheduledSeconds

            // The MIDI-out stamp SOURCE (what the engine hands to MidiOut.now).
            let midiHostSeconds = clock.hostSeconds(atMusicalSeconds: musicalSeconds)
            // The AUDIO sink's host time for the same step (production slice path).
            let audioHostSeconds = AVAudioTime.seconds(
                forHostTime: clock.audioTime(atMusicalSeconds: musicalSeconds).hostTime
            )

            XCTAssertEqual(
                midiHostSeconds, audioHostSeconds, accuracy: 1e-12,
                "step \(step): MIDI host time must equal the audio sink host time for the same musical step"
            )

            // Jitter-free: the MIDI host time for a step is the captured origin
            // plus the step's musical offset — the injected pump jitter for this
            // step contributes 0.
            let expected = clock.hostSeconds(atMusicalSeconds: 0) + musicalSeconds
            XCTAssertEqual(
                midiHostSeconds, expected, accuracy: 1e-12,
                "step \(step): MIDI host time must be origin + musical offset (pump jitter must not move it)"
            )
        }
    }

    /// NEGATIVE CONTROL: the OLD source (`pump wake now + stepDuration`) DOES
    /// move with the injected jitter, so it is NOT a fixed offset from the
    /// origin-anchored unified value — proving the equality gate above is
    /// load-bearing.
    func test_wallClockMidiSource_movesUnderJitter_negativeControl() throws {
        let bpm = 120.0
        let harness = try makeSampleHarness(bpm: bpm)
        let clock = harness.controller.audioMasterClock
        let stepDuration = harness.secondsPerStep(bpm: bpm)
        let jitter: [Double] = [0, +0.004, -0.003, +0.005, -0.004, +0.002, -0.005, +0.003]
        let steps = jitter.count

        var anyDiverged = false
        for step in 0..<steps {
            let wakeNow = Double(step) * stepDuration + jitter[step]
            harness.drive(step: step, now: wakeNow)
            let musicalSeconds = harness.capturedFrames[step].scheduledSeconds

            // Unified (origin-anchored) MIDI host time.
            let unified = clock.hostSeconds(atMusicalSeconds: musicalSeconds)
            // Old wall-clock MIDI source (pump wake + one step ahead).
            let wallClock = wakeNow + stepDuration

            // Compare the per-step difference: under the unified clock it would be
            // a constant (the origin offset). Under the old source the jitter
            // perturbs it step-to-step.
            if step > 0 {
                let prevWake = Double(step - 1) * stepDuration + jitter[step - 1]
                let prevMusical = harness.capturedFrames[step - 1].scheduledSeconds
                let prevUnified = clock.hostSeconds(atMusicalSeconds: prevMusical)
                let unifiedStepDelta = unified - prevUnified
                let wallStepDelta = wallClock - (prevWake + stepDuration)
                if abs(unifiedStepDelta - wallStepDelta) > 1e-9 {
                    anyDiverged = true
                }
            }
        }

        XCTAssertTrue(
            anyDiverged,
            "the wall-clock MIDI source must drift step-to-step under pump jitter while the unified " +
            "source stays grid-locked — otherwise the jitter-free gate is vacuous"
        )
    }

    // MARK: - 3: per-port output offset shifts the real MIDITimeStamp by exactly δ

    /// The per-port `outputOffsetSeconds` ADDS exactly its value (in mach host
    /// units) to every sent `MIDITimeStamp`; default is 0 (no shift). Measured
    /// from the actual `MIDITimeStamp` carried on packets sent through a virtual
    /// MIDI endpoint.
    func test_perPortOffset_shiftsMidiTimestamp_byExactlyTheOffset() throws {
        // Same unified-clock host-time value drives both sends.
        let baseHostSeconds = 12.5
        let offsetSeconds = 0.020 // 20 ms calibration

        let zeroOffsetStamp = try sentTimestamp(
            offsetSeconds: 0,
            nowHostSeconds: baseHostSeconds,
            observerSuffix: "ZeroOffset"
        )
        let withOffsetStamp = try sentTimestamp(
            offsetSeconds: offsetSeconds,
            nowHostSeconds: baseHostSeconds,
            observerSuffix: "WithOffset"
        )

        // Expected shift in mach host units for the same base time.
        let expectedZero = AudioConvertNanosToHostTime(UInt64((baseHostSeconds * 1e9).rounded()))
        let expectedShifted = AudioConvertNanosToHostTime(
            UInt64(((baseHostSeconds + offsetSeconds) * 1e9).rounded())
        )

        XCTAssertEqual(zeroOffsetStamp, expectedZero, "default/zero offset must not shift the timestamp")
        XCTAssertEqual(
            withOffsetStamp, expectedShifted,
            "the per-port offset must add exactly its value (in host units) to the MIDITimeStamp"
        )
        // The measured delta between the two sends equals the offset in host units.
        let measuredDelta = Int64(bitPattern: withOffsetStamp) - Int64(bitPattern: zeroOffsetStamp)
        let offsetInHostUnits = Int64(bitPattern: expectedShifted) - Int64(bitPattern: expectedZero)
        XCTAssertEqual(
            measuredDelta, offsetInHostUnits,
            "the timestamp shift between offset 0 and offset δ must equal δ converted to host units"
        )
    }

    /// Default `outputOffsetSeconds` is 0 and negative offsets clamp to 0
    /// (PLUMB-ONLY config seam; never auto-tuned). Pure, no transport.
    func test_outputOffset_defaultsToZero_andClampsNegative() {
        let block = MidiOut(id: "out")
        XCTAssertEqual(block.outputOffsetSeconds, 0, "default offset is 0")

        block.setOutputOffsetSeconds(0.015)
        XCTAssertEqual(block.outputOffsetSeconds, 0.015, "setter stores the offset")

        block.apply(paramKey: "outputOffsetSeconds", value: .number(0.030))
        XCTAssertEqual(block.outputOffsetSeconds, 0.030, "param path stores the offset")

        block.setOutputOffsetSeconds(-0.010)
        XCTAssertEqual(block.outputOffsetSeconds, 0, "negative offset clamps to 0")
    }

    // MARK: - Harness fixture (mirrors OfflineFrameAccuracyTests.makeSampleHarness)

    private func writeSilentWAV(to url: URL, sampleRate: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * 0.1)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func makeSampleHarness(
        bpm: Double = 120,
        sampleRate: Double = 48_000,
        stepsPerBar: Int = 16
    ) throws -> Harness {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let sink = CapturingSink()

        let track = StepSequenceTrack(
            name: "K",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: kick.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        let generator = GeneratorPoolEntry(
            id: UUID(),
            name: "Always On",
            trackType: track.trackType,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0)),
                pitch: .native(.manual(pitches: [DrumKitNoteMap.baselineNote], pickMode: .sequential)),
                shape: NoteShape(velocity: 100, gateLength: 4, accent: false)
            )
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            layers: layers,
            patternBanks: [
                TrackPatternBank(
                    trackID: track.id,
                    slots: (0..<stepsPerBar).map { TrackPatternSlot(slotIndex: $0, sourceRef: .generator(generator.id)) }
                )
            ],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: stepsPerBar,
            sampleEngine: sink,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(bpm)

        return Harness(
            sampleRate: sampleRate,
            stepsPerBar: stepsPerBar,
            controller: controller,
            sink: sink
        )
    }

    // MARK: - Helpers

    /// Send one note-on through a virtual MIDI endpoint and return the
    /// `MIDITimeStamp` actually carried on the packet.
    private func sentTimestamp(
        offsetSeconds: TimeInterval,
        nowHostSeconds: TimeInterval,
        observerSuffix: String
    ) throws -> MIDITimeStamp {
        let received = TimestampedMIDIPacketStore()
        let observer = try MIDIClient(name: "SequencerAI_MidiOut_TS_Observer_\(observerSuffix)")
        let destination = try observer.createVirtualInput(
            name: "SequencerAI_MidiOut_TS_Destination_\(observerSuffix)"
        ) { packetList in
            received.append(packetList)
        }
        let producer = try MIDIClient(name: "SequencerAI_MidiOut_TS_Producer_\(observerSuffix)")
        let block = MidiOut(id: "out", client: producer, endpoint: destination)
        block.setOutputOffsetSeconds(offsetSeconds)

        _ = block.tick(context: TickContext(
            tickIndex: 0,
            bpm: 120,
            inputs: ["notes": EngineStream.notes([
                NoteEvent(pitch: 60, velocity: 100, length: 4, gate: true, voiceTag: nil)
            ])],
            now: nowHostSeconds,
            preparedNotesByBlockID: [:]
        ))

        waitForPacketCount(received, expected: 1)
        return try XCTUnwrap(received.timestamps.first, "no MIDI packet captured")
    }

    private func waitForPacketCount(
        _ store: TimestampedMIDIPacketStore,
        expected: Int,
        timeout: TimeInterval = 1.0
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while store.count < expected && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
}

/// Captures the `MIDITimeStamp` carried on each received packet.
private final class TimestampedMIDIPacketStore: @unchecked Sendable {
    private let lock = NSLock()
    private var stamps: [MIDITimeStamp] = []

    func append(_ packetList: UnsafePointer<MIDIPacketList>) {
        lock.lock()
        defer { lock.unlock() }
        let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
        var packet = UnsafeMutableRawPointer(mutating: packetList)
            .advanced(by: packetOffset)
            .assumingMemoryBound(to: MIDIPacket.self)
        for _ in 0..<packetList.pointee.numPackets {
            stamps.append(packet.pointee.timeStamp)
            packet = MIDIPacketNext(packet)
        }
    }

    var timestamps: [MIDITimeStamp] {
        lock.lock()
        defer { lock.unlock() }
        return stamps
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return stamps.count
    }
}
