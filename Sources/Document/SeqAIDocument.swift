import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let seqAIDocument = UTType(exportedAs: "ai.sequencer.document")
}

struct SeqAIDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.seqAIDocument] }
    static var writableContentTypes: [UTType] { [.seqAIDocument] }

    var runtimeID = UUID()
    var project: Project

    init(project: Project = .empty) {
        self.project = project
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.project = try JSONDecoder().decode(Project.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let projectForWriting = SeqAIDocumentProjectionRegistry.projectForWriting(
            runtimeID: runtimeID,
            fallback: project
        )
        let data = try encoder.encode(projectForWriting)
        return FileWrapper(regularFileWithContents: data)
    }
}
