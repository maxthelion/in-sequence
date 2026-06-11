import AVFoundation
import XCTest
@testable import SequencerAI

final class MasterRenderTests: XCTestCase {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("master-render-\(UUID().uuidString).wav")
    }

    private func tmpDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("master-render-\(UUID().uuidString)", isDirectory: true)
    }

    func test_startStop_roundTripCreatesReadableFile() throws {
        let graph = MainAudioGraph()
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(graph.startMasterRender(to: url))
        XCTAssertTrue(graph.isMasterRenderActive)
        XCTAssertFalse(graph.startMasterRender(to: tmpURL()), "second concurrent render must be refused")

        // Push synthetic audio through the write path (no running engine).
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        buffer.frameLength = 512
        for ch in 0..<2 {
            let samples = buffer.floatChannelData![ch]
            for i in 0..<512 { samples[i] = sinf(Float(i) * 0.1) * 0.5 }
        }
        graph.writeMasterRenderBufferForTesting(buffer)
        graph.writeMasterRenderBufferForTesting(buffer)

        XCTAssertEqual(graph.stopMasterRender(), url)
        XCTAssertFalse(graph.isMasterRenderActive)
        XCTAssertNil(graph.stopMasterRender())

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.length, 1024)
        // Content survived: non-silent RMS.
        let read = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024)!
        try file.read(into: read)
        var sum: Float = 0
        let data = read.floatChannelData![0]
        for i in 0..<Int(read.frameLength) { sum += data[i] * data[i] }
        XCTAssertGreaterThan(sum / Float(read.frameLength), 0.01)
    }

    func test_writeWithoutActiveRender_isNoOp() {
        let graph = MainAudioGraph()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)!
        buffer.frameLength = 64
        graph.writeMasterRenderBufferForTesting(buffer)
        XCTAssertFalse(graph.isMasterRenderActive)
    }

    func test_sampleTrackRendersNonSilentAudioAtMasterOutput() throws {
        let sampleRoot = tmpDirectory()
        defer { try? FileManager.default.removeItem(at: sampleRoot) }
        let kickDirectory = sampleRoot.appendingPathComponent("kick", isDirectory: true)
        try FileManager.default.createDirectory(at: kickDirectory, withIntermediateDirectories: true)
        try writeClickWAV(to: kickDirectory.appendingPathComponent("diagnostic-click.wav"))

        let library = AudioSampleLibrary(libraryRoot: sampleRoot)
        let sample = try XCTUnwrap(library.firstSample(in: .kick))
        let track = StepSequenceTrack(
            name: "Diagnostic Sample",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: sample.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        let generatorID = UUID()
        let generator = GeneratorPoolEntry(
            id: generatorID,
            name: "Every Step",
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
                    slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generatorID))]
                )
            ],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            mainAudioGraph: audioGraph,
            sampleEngine: sampleEngine,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        XCTAssertEqual(sampleEngine.preparedTrackIDs, [track.id])
        XCTAssertTrue(sampleEngine.isFirstPreparedVoiceConnectedForTesting(trackID: track.id))

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(controller.startMasterRender(to: renderURL))
        controller.start()
        XCTAssertTrue(sampleEngine.isFirstPreparedVoiceConnectedForTesting(trackID: track.id))
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        controller.stop()
        XCTAssertEqual(controller.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "A real sample track should reach the master output render tap.")
    }

    func test_directSamplePlaybackEngineRendersNonSilentAudioAtMasterOutput() throws {
        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)

        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let trackID = UUID()
        sampleEngine.prepareTrack(trackID: trackID)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        defer { sampleEngine.stop() }

        XCTAssertNotNil(sampleEngine.play(sampleURL: sampleURL, settings: .default, trackID: trackID, at: nil))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Direct sample playback should reach the master output render tap.")
    }

    func test_directSamplePlaybackWithMasterBusHostRendersNonSilentAudioAtMasterOutput() throws {
        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)

        let audioGraph = MainAudioGraph()
        let masterBusHost = MasterBusHost()
        masterBusHost.attach(to: audioGraph)
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let trackID = UUID()
        sampleEngine.prepareTrack(trackID: trackID)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        defer { sampleEngine.stop() }

        XCTAssertNotNil(sampleEngine.play(sampleURL: sampleURL, settings: .default, trackID: trackID, at: nil))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Master bus host should not disconnect sample playback from the master output.")
    }

    func test_directSamplePlaybackEngineRendersScheduledHostTimeAudioAtMasterOutput() throws {
        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)

        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let trackID = UUID()
        sampleEngine.prepareTrack(trackID: trackID)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        defer { sampleEngine.stop() }

        let hostTime = AVAudioTime.hostTime(forSeconds: ProcessInfo.processInfo.systemUptime)
        XCTAssertNotNil(sampleEngine.play(
            sampleURL: sampleURL,
            settings: .default,
            trackID: trackID,
            at: AVAudioTime(hostTime: hostTime)
        ))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Scheduled host-time sample playback should reach the master output render tap.")
    }

    func test_directSamplePlaybackEngineRendersStaleScheduledHostTimeAudioAtMasterOutput() throws {
        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)

        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let trackID = UUID()
        sampleEngine.prepareTrack(trackID: trackID)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        defer { sampleEngine.stop() }

        let staleSeconds = ProcessInfo.processInfo.systemUptime - 0.05
        let hostTime = AVAudioTime.hostTime(forSeconds: staleSeconds)
        XCTAssertNotNil(sampleEngine.play(
            sampleURL: sampleURL,
            settings: .default,
            trackID: trackID,
            at: AVAudioTime(hostTime: hostTime)
        ))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Slightly stale sample triggers should degrade to immediate playback, not silence.")
    }

    func test_directSamplePlaybackEngineRendersOffMainScheduledAudioAtMasterOutput() throws {
        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)

        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let trackID = UUID()
        sampleEngine.prepareTrack(trackID: trackID)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        defer { sampleEngine.stop() }

        let dispatched = expectation(description: "off-main dispatch returned")
        DispatchQueue(label: "MasterRenderTests.off-main-sample-play").async {
            let hostTime = AVAudioTime.hostTime(forSeconds: ProcessInfo.processInfo.systemUptime)
            _ = sampleEngine.play(
                sampleURL: sampleURL,
                settings: .default,
                trackID: trackID,
                at: AVAudioTime(hostTime: hostTime)
            )
            dispatched.fulfill()
        }

        wait(for: [dispatched], timeout: 1)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Off-main scheduled sample playback should reach the master output render tap.")
    }

    private func writeClickWAV(to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frameCount = AVAudioFrameCount(4_410)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frameCount) {
            let envelope = max(0, 1 - (Float(index) / Float(frameCount)))
            samples[index] = sinf(Float(index) * 0.45) * envelope * 0.8
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func rmsOfFirstChannel(at url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )!
        try file.read(into: buffer)
        guard buffer.frameLength > 0,
              let channel = buffer.floatChannelData?[0]
        else { return 0 }

        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            sum += channel[index] * channel[index]
        }
        return sqrt(sum / Float(buffer.frameLength))
    }
}
