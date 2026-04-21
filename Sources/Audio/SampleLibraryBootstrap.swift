import Foundation
import CryptoKit

enum SampleLibraryBootstrap {
    /// ~/Library/Application Support/sequencer-ai/samples/
    static var applicationSupportSamplesURL: URL {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base
            .appendingPathComponent("sequencer-ai", isDirectory: true)
            .appendingPathComponent("samples", isDirectory: true)
    }

    /// <app-bundle>/Resources/StarterSamples/ — nil in a non-bundle context (unit tests).
    static var bundledSamplesURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("StarterSamples", isDirectory: true)
    }

    struct Manifest: Codable, Equatable {
        var version: String
        var files: [String: String]    // relativePath → SHA256 hex
    }

    /// Idempotent. Copies bundled starters into Application Support when:
    ///   (a) the Application Support samples directory is missing, or
    ///   (b) the bundled manifest's per-file SHA differs from the installed one.
    /// Only files whose SHA differs are overwritten. Files present in Application Support
    /// but absent from the bundle are left untouched (future user-imported content).
    @discardableResult
    static func ensureLibraryInstalled(
        bundleSamplesURL: URL? = bundledSamplesURL,
        destinationURL: URL = applicationSupportSamplesURL
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        guard let bundleSamplesURL,
              fm.fileExists(atPath: bundleSamplesURL.path)
        else {
            return destinationURL
        }

        let bundledManifest = try loadManifest(from: bundleSamplesURL.appendingPathComponent("manifest.json"))
        let installedManifestURL = destinationURL.appendingPathComponent("manifest.json")
        let installedManifest = (try? loadManifest(from: installedManifestURL)) ?? Manifest(version: "", files: [:])

        var didChange = false
        for (relativePath, bundledHash) in bundledManifest.files {
            if installedManifest.files[relativePath] == bundledHash {
                continue
            }
            let src = bundleSamplesURL.appendingPathComponent(relativePath)
            let dst = destinationURL.appendingPathComponent(relativePath)
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
            didChange = true
        }

        if didChange || !fm.fileExists(atPath: installedManifestURL.path) {
            let data = try JSONEncoder().encode(bundledManifest)
            try data.write(to: installedManifestURL, options: .atomic)
        }

        return destinationURL
    }

    private static func loadManifest(from url: URL) throws -> Manifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }
}
