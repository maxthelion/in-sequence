import AVFoundation
import Foundation
import Observation

/// Sidecar metadata for one recorded take. Persisted as JSON next to the WAV
/// under `<libraryRoot>/recordings/`.
struct RecordingAsset: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// Stable ID derived from the WAV's library-relative path with
    /// `AudioSampleLibrary.stableID(forRelativePath:)`, so the same take has
    /// the same ID whether it is referenced as a recording or as a sample.
    let id: UUID
    var name: String
    var capturedAt: Date
    var barCount: Int
    /// Transport BPM at capture time.
    var bpm: Double
    var sourceTrackName: String
    var sampleRate: Double
    var channelCount: Int
    var lengthFrames: Int64
    /// WAV filename inside the recordings directory.
    var fileName: String

    var lengthSeconds: Double? {
        guard sampleRate > 0 else { return nil }
        return Double(lengthFrames) / sampleRate
    }
}

/// Global library of recorded audio-input takes, beside the sample library
/// (pattern: `DrumAssetLibrary`). Owns `<libraryRoot>/recordings/*.wav` plus a
/// JSON sidecar per take. Writes happen off the main thread (the engine's
/// persistence queue); the observable `recordings` list is updated on main.
@Observable
final class RecordingLibrary {
    enum StoreError: Error, Equatable {
        case emptyPCM
        case unsupportedFormat
    }

    static let shared: RecordingLibrary = {
        do {
            let root = try SampleLibraryBootstrap.ensureLibraryInstalled()
            return RecordingLibrary(libraryRoot: root)
        } catch {
            NSLog("[RecordingLibrary] bootstrap failed: \(error) — recordings will be empty")
            return RecordingLibrary(libraryRoot: SampleLibraryBootstrap.applicationSupportSamplesURL)
        }
    }()

    let libraryRoot: URL
    private(set) var recordings: [RecordingAsset]

    /// Directory name doubles as the `AudioSampleCategory.recordings` raw
    /// value so the sample library's scan picks recordings up as samples.
    static let recordingsDirectoryName = AudioSampleCategory.recordings.rawValue

    var recordingsDirectory: URL {
        libraryRoot.appendingPathComponent(Self.recordingsDirectoryName, isDirectory: true)
    }

    init(libraryRoot: URL) {
        self.libraryRoot = libraryRoot
        self.recordings = Self.loadSidecars(
            in: libraryRoot.appendingPathComponent(Self.recordingsDirectoryName, isDirectory: true)
        )
    }

    func reload() {
        recordings = Self.loadSidecars(in: recordingsDirectory)
    }

    // MARK: - Queries

    func recording(id: UUID) -> RecordingAsset? {
        recordings.first(where: { $0.id == id })
    }

    func fileURL(for asset: RecordingAsset) -> URL {
        recordingsDirectory.appendingPathComponent(asset.fileName)
    }

    /// Library-relative path of the take's WAV (used for stable sample IDs).
    static func relativePath(forFileName fileName: String) -> String {
        "\(recordingsDirectoryName)/\(fileName)"
    }

    // MARK: - Store

    /// Write a captured take (WAV + sidecar) into the library. Callable from
    /// any thread; performs blocking file IO, so never call on main or the
    /// engine tick path. The observable `recordings` list updates on main.
    @discardableResult
    func storeRecording(
        pcm: AudioInputCapturedPCM,
        sourceTrackName: String,
        barCount: Int,
        bpm: Double,
        capturedAt: Date = Date()
    ) throws -> RecordingAsset {
        guard pcm.frameCount > 0, pcm.channelCount > 0, pcm.sampleRate > 0 else {
            throw StoreError.emptyPCM
        }

        let fm = FileManager.default
        let directory = recordingsDirectory
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let trackName = Self.sanitized(sourceTrackName.isEmpty ? "Audio Input" : sourceTrackName)
        let takeNumber = nextTakeNumber(sourceTrackName: trackName, in: directory)
        let name = "\(trackName) — \(barCount) bar\(barCount == 1 ? "" : "s") — take \(takeNumber)"
        let fileName = "\(name).wav"
        let fileURL = directory.appendingPathComponent(fileName)

        guard let buffer = pcm.makePCMBuffer() else {
            throw StoreError.unsupportedFormat
        }
        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: pcm.sampleRate,
                AVNumberOfChannelsKey: pcm.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)

        let asset = RecordingAsset(
            id: AudioSampleLibrary.stableID(forRelativePath: Self.relativePath(forFileName: fileName)),
            name: name,
            // ISO8601 sidecar dates carry whole seconds; normalize so the
            // in-memory asset equals its disk round-trip.
            capturedAt: Date(timeIntervalSince1970: capturedAt.timeIntervalSince1970.rounded(.down)),
            barCount: barCount,
            bpm: bpm,
            sourceTrackName: trackName,
            sampleRate: pcm.sampleRate,
            channelCount: pcm.channelCount,
            lengthFrames: Int64(pcm.frameCount),
            fileName: fileName
        )

        let sidecarURL = directory.appendingPathComponent("\(name).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(asset).write(to: sidecarURL, options: .atomic)

        register(asset)
        return asset
    }

    /// Append a stored asset to the observable list on the main thread.
    /// `@Observable` mutations must not happen off-main (SwiftUI observers
    /// run synchronously inside the registrar's willSet).
    private func register(_ asset: RecordingAsset) {
        let apply = { [weak self] in
            guard let self else { return }
            self.recordings.removeAll { $0.id == asset.id }
            self.recordings.append(asset)
            self.recordings.sort { $0.capturedAt < $1.capturedAt }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    // MARK: - Scan

    /// Take numbering reads sidecars from disk (not the observable list) so
    /// it is correct when called from the persistence queue while `recordings`
    /// still awaits its main-thread update.
    private func nextTakeNumber(sourceTrackName: String, in directory: URL) -> Int {
        let existing = Self.loadSidecars(in: directory)
            .filter { $0.sourceTrackName == sourceTrackName }
        return existing.count + 1
    }

    private static func loadSidecars(in directory: URL) -> [RecordingAsset] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let sidecars = files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var assets: [RecordingAsset] = []
        for fileURL in sidecars {
            do {
                let data = try Data(contentsOf: fileURL)
                assets.append(try decoder.decode(RecordingAsset.self, from: data))
            } catch {
                NSLog("[RecordingLibrary] skipping unreadable sidecar \(fileURL.lastPathComponent): \(error)")
            }
        }
        return assets.sorted { $0.capturedAt < $1.capturedAt }
    }

    private static func sanitized(_ name: String) -> String {
        name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension AudioInputCapturedPCM {
    /// Deinterleaved float32 buffer of the captured loop, for playback or
    /// file writes.
    func makePCMBuffer() -> AVAudioPCMBuffer? {
        guard frameCount > 0,
              channelCount > 0,
              let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: AVAudioChannelCount(channelCount)
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              )
        else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let destinationChannels = buffer.floatChannelData else {
            return nil
        }
        for channel in 0..<channelCount {
            channels[channel].withUnsafeBufferPointer { source in
                guard let baseAddress = source.baseAddress else { return }
                destinationChannels[channel].update(from: baseAddress, count: frameCount)
            }
        }
        return buffer
    }
}
