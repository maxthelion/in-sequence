import Foundation

enum VisualFixtureDocumentLoader {
    static let environmentKey = "SEQUENCER_AI_NEW_DOCUMENT_FIXTURE"

    static func projectFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> Project? {
        guard let rawPath = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty
        else {
            return nil
        }

        do {
            return try loadProject(at: fixtureURL(for: rawPath, currentDirectory: currentDirectory))
        } catch {
            NSLog("[VisualFixtureDocumentLoader] failed to load fixture %@: %@", rawPath, String(describing: error))
            return nil
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
