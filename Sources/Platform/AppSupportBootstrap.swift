import Foundation

enum AppSupportBootstrap {
    /// Subfolders relative to the app-support root that must exist for the library to be usable.
    static let librarySubfolders: [String] = [
        "library/templates",
        "library/voice-presets",
        "library/fill-presets",
        "library/takes",
        "library/chord-gen-presets",
        "library/slice-sets",
        "library/phrases",
    ]

    /// Creates every required subfolder under `root`. Idempotent.
    static func ensureLibraryStructure(root: URL) throws {
        for sub in librarySubfolders {
            let url = root.appendingPathComponent(sub)
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }
    }

    /// Returns the canonical app-support directory for this application, creating the
    /// `Application Support/sequencer-ai` container if missing.
    static func appSupportRoot() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("sequencer-ai", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
