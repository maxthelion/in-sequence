import Foundation

enum VisualFixtureDocumentLoader {
    static let environmentKey = "SEQUENCER_AI_NEW_DOCUMENT_FIXTURE"

    /// When set to "1", the loader writes the AudioRichFixture's generated WAVs
    /// (the four drum one-shots + the slicer loop) into the live
    /// AudioSampleLibrary tree before the loaded document's samples are
    /// resolved/scanned, so the `.sample(...)` / `.slicer(...)` destinations in
    /// the audio-rich fixture actually render. No effect unless the env is set.
    static let materializeSamplesEnvironmentKey = "SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES"

    static func projectFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> Project? {
        guard let rawPath = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty
        else {
            return nil
        }

        // Env-gated, least-invasive hook: SequencerAIApp constructs the new
        // document via this function and AudioSampleLibrary.shared is already
        // warmed by the time the DocumentGroup runs, so materializing here
        // guarantees the generated samples exist on disk before the document's
        // sample/slicer destinations are resolved. The app entry points
        // (SequencerAIApp / AppDelegate) are off-limits; this is the cleanest
        // allowed call site. Gated strictly on the env so normal runs are
        // unaffected.
        materializeFixtureSamplesIfRequested(environment)

        do {
            return try loadProject(at: fixtureURL(for: rawPath, currentDirectory: currentDirectory))
        } catch {
            NSLog("[VisualFixtureDocumentLoader] failed to load fixture %@: %@", rawPath, String(describing: error))
            return nil
        }
    }

    /// Materializes the AudioRichFixture's generated WAVs into the live sample
    /// library tree, but ONLY when `SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES`
    /// is "1". Best-effort: failures are logged, never fatal.
    static func materializeFixtureSamplesIfRequested(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard environment[materializeSamplesEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        else {
            return
        }
        do {
            try AudioRichFixture.materializeAllSamples(libraryRoot: AudioSampleLibrary.shared.libraryRoot)
            NSLog("[VisualFixtureDocumentLoader] materialized audio-rich fixture samples into %@",
                  AudioSampleLibrary.shared.libraryRoot.path)
        } catch {
            NSLog("[VisualFixtureDocumentLoader] fixture sample materialization failed: %@", String(describing: error))
        }
    }

    static func loadProject(at url: URL) throws -> Project {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Project.self, from: data)
    }

    static func fixtureURL(for rawPath: String, currentDirectory: URL) -> URL {
        let expandedPath = (rawPath as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath)
        }
        return currentDirectory.appendingPathComponent(expandedPath)
    }
}
