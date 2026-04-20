import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let seqAIDocument = UTType(exportedAs: "ai.sequencer.document")
}

struct SeqAIDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.seqAIDocument] }
    static var writableContentTypes: [UTType] { [.seqAIDocument] }

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
        let data = try encoder.encode(project)
        return FileWrapper(regularFileWithContents: data)
    }
}
