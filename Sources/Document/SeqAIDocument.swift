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

    /// Called by SwiftUI/AppKit before `fileWrapper(snapshot:configuration:)`.
    /// Flushes any pending live-store edits into `self.project` so the save always
    /// captures the freshest state when the snapshot hook is invoked on main.
    func snapshot(contentType: UTType) throws -> Project {
        // SwiftUI/AppKit can invoke ReferenceFileDocument serialization on a
        // background save queue. Do not sync-hop to main from here: during save
        // AppKit may already be waiting on the worker, which would deadlock.
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                SequencerDocumentSessionRegistry.session(for: self)?.flushToDocumentSync()
            }
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
