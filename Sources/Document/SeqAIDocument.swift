import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let seqAIDocument = UTType(exportedAs: "ai.sequencer.document")
}

struct SeqAIDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.seqAIDocument] }
    static var writableContentTypes: [UTType] { [.seqAIDocument] }

    var model: SeqAIDocumentModel

    init(model: SeqAIDocumentModel = .empty) {
        self.model = model
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.model = try JSONDecoder().decode(SeqAIDocumentModel.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(model)
        return FileWrapper(regularFileWithContents: data)
    }
}
