import Foundation
import AVFoundation
import CryptoKit
import Observation

@Observable
final class AudioSampleLibrary {
    /// UUIDv5 namespace used to derive sample IDs from relative paths.
    /// DO NOT CHANGE — IDs are persisted in documents. Generated once for this plan.
    private static let namespace: UUID = UUID(uuidString: "9B3F4D8A-2E1B-4B5D-9A6C-7F8E9D0C1B2A")!

    static let shared: AudioSampleLibrary = {
        do {
            let root = try SampleLibraryBootstrap.ensureLibraryInstalled()
            return AudioSampleLibrary(libraryRoot: root)
        } catch {
            NSLog("[AudioSampleLibrary] bootstrap failed: \(error) — library will be empty")
            return AudioSampleLibrary(libraryRoot: SampleLibraryBootstrap.applicationSupportSamplesURL)
        }
    }()

    private(set) var samples: [AudioSample]
    let libraryRoot: URL

    init(libraryRoot: URL) {
        self.libraryRoot = libraryRoot
        self.samples = Self.scan(root: libraryRoot)
    }

    func reload() {
        samples = Self.scan(root: libraryRoot)
    }

    // MARK: - Queries

    func sample(id: UUID) -> AudioSample? {
        samples.first(where: { $0.id == id })
    }

    func samples(in category: AudioSampleCategory) -> [AudioSample] {
        samples.filter { $0.category == category }
    }

    func firstSample(in category: AudioSampleCategory) -> AudioSample? {
        samples(in: category).first
    }

    func nextSample(after id: UUID) -> AudioSample? {
        guard let current = sample(id: id) else { return nil }
        let peers = samples(in: current.category)
        guard !peers.isEmpty, let idx = peers.firstIndex(of: current) else { return nil }
        return peers[(idx + 1) % peers.count]
    }

    func previousSample(before id: UUID) -> AudioSample? {
        guard let current = sample(id: id) else { return nil }
        let peers = samples(in: current.category)
        guard !peers.isEmpty, let idx = peers.firstIndex(of: current) else { return nil }
        return peers[(idx - 1 + peers.count) % peers.count]
    }

    // MARK: - Scan

    private static func scan(root: URL) -> [AudioSample] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }

        let supportedExtensions: Set<String> = ["wav", "aif", "aiff", "caf"]
        var found: [AudioSample] = []

        guard let topLevel = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for categoryDir in topLevel where (try? categoryDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let categoryName = categoryDir.lastPathComponent
            let category = AudioSampleCategory(rawValue: categoryName) ?? .unknown
            if category == .unknown {
                NSLog("[AudioSampleLibrary] unknown category directory: \(categoryName)")
            }

            guard let files = try? fm.contentsOfDirectory(
                at: categoryDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            let audioFiles = files
                .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            for fileURL in audioFiles {
                let relativePath = "\(categoryName)/\(fileURL.lastPathComponent)"
                let id = uuidV5(namespace: namespace, name: relativePath)
                let name = (fileURL.lastPathComponent as NSString).deletingPathExtension
                let length = audioLengthSeconds(url: fileURL)
                found.append(AudioSample(
                    id: id,
                    name: name,
                    fileRef: .appSupportLibrary(relativePath: relativePath),
                    category: category,
                    lengthSeconds: length
                ))
            }
        }

        return found
    }

    private static func audioLengthSeconds(url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let frames = Double(file.length)
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { return nil }
        return frames / rate
    }

    private static func uuidV5(namespace: UUID, name: String) -> UUID {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: namespace.uuid) { buf in bytes.append(contentsOf: buf) }
        bytes.append(contentsOf: Array(name.utf8))
        let digest = Insecure.SHA1.hash(data: bytes)
        var out = Array(digest.prefix(16))
        out[6] = (out[6] & 0x0F) | 0x50
        out[8] = (out[8] & 0x3F) | 0x80
        return UUID(uuid: (
            out[0], out[1], out[2], out[3],
            out[4], out[5], out[6], out[7],
            out[8], out[9], out[10], out[11],
            out[12], out[13], out[14], out[15]
        ))
    }
}
