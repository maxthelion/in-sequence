import XCTest
@testable import SequencerAI

@MainActor
final class TransportDocumentEditCommandTests: XCTestCase {
    func testCommandsMapAvailabilityToTheirButtons() {
        let availability = DocumentEditCommandController.Availability(
            canCopy: true,
            canPaste: false,
            canClear: true
        )

        XCTAssertTrue(TransportDocumentEditCommand.copy.isEnabled(in: availability))
        XCTAssertFalse(TransportDocumentEditCommand.paste.isEnabled(in: availability))
        XCTAssertTrue(TransportDocumentEditCommand.clearSelection.isEnabled(in: availability))
    }

    func testCommandsExposeStableAccessibleMetadata() {
        XCTAssertEqual(TransportDocumentEditCommand.copy.accessibilityIdentifier, "transport-copy")
        XCTAssertEqual(TransportDocumentEditCommand.copy.helpText, "Copy selection")
        XCTAssertEqual(TransportDocumentEditCommand.paste.accessibilityIdentifier, "transport-paste")
        XCTAssertEqual(TransportDocumentEditCommand.paste.helpText, "Paste into selection")
        XCTAssertEqual(
            TransportDocumentEditCommand.clearSelection.accessibilityIdentifier,
            "transport-clear-selection"
        )
        XCTAssertEqual(TransportDocumentEditCommand.clearSelection.helpText, "Clear selection")
        XCTAssertEqual(TransportDocumentEditCommand.clearSelection.accessibilityLabel, "Clear selection")
    }

    func testCommandsExecuteControllerActions() {
        let controller = DocumentEditCommandController()
        let domain: DocumentEditCommandController.Domain = "steps"
        var pasteCount = 0
        var clearCount = 0

        controller.register(target: .init(
            canCopy: { true },
            canClear: { true },
            isPasteCompatible: { $0.domain == domain },
            copy: { .init(domain: domain, snapshot: [7, 8]) },
            paste: { _ in pasteCount += 1 },
            clearSelection: { clearCount += 1 }
        ))

        XCTAssertTrue(TransportDocumentEditCommand.copy.perform(on: controller))
        XCTAssertTrue(TransportDocumentEditCommand.paste.perform(on: controller))
        XCTAssertTrue(TransportDocumentEditCommand.clearSelection.perform(on: controller))
        XCTAssertEqual(pasteCount, 1)
        XCTAssertEqual(clearCount, 1)
    }
}
