import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let seqAIDocument = UTType(exportedAs: "ai.sequencer.document")
}

final class SeqAIDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.seqAIDocument] }
    static var writableContentTypes: [UTType] { [.seqAIDocument] }

    var project: Project

    init(project: Project = .empty) {
        self.project = project
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.project = try JSONDecoder().decode(Project.self, from: data)
    }

    /// Called by SwiftUI on the main thread before `fileWrapper(snapshot:configuration:)`.
    /// Flushes any pending live-store edits into `self.project` so the save always
    /// captures the freshest state, even within the debounce window.
    func snapshot(contentType: UTType) throws -> Project {
        // SwiftUI calls snapshot(contentType:) on the main thread. We assume that
        // invariant here so we can safely access @MainActor-isolated registry state.
        MainActor.assumeIsolated {
            SequencerDocumentSessionRegistry.session(for: self)?.flushToDocumentSync()
        }
        return project
    }

    func fileWrapper(snapshot: Project, configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        return FileWrapper(regularFileWithContents: data)
    }
}
