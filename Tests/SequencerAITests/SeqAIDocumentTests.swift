import XCTest
@testable import SequencerAI

final class SeqAIDocumentModelTests: XCTestCase {
    func test_empty_has_version_1() {
        let model = SeqAIDocumentModel.empty
        XCTAssertEqual(model.version, 1)
    }

    func test_codable_roundtrip_preserves_empty() throws {
        let original = SeqAIDocumentModel.empty
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SeqAIDocumentModel.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

import UniformTypeIdentifiers

final class SeqAIDocumentFileTests: XCTestCase {
    func test_readable_content_types_includes_seqai_utype() {
        XCTAssertTrue(SeqAIDocument.readableContentTypes.contains(.seqAIDocument))
    }

    func test_default_initializer_creates_empty_model() {
        let doc = SeqAIDocument()
        XCTAssertEqual(doc.model, .empty)
    }
}
