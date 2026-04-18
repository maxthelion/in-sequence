import Foundation

struct SeqAIDocumentModel: Codable, Equatable {
    var version: Int

    static let empty = SeqAIDocumentModel(version: 1)
}
