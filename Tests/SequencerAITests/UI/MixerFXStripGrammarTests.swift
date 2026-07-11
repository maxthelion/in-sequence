import XCTest

/// Source-level guard for the compact mixer FX strip grammar requested in the
/// owner bug cluster. These SwiftUI pieces do not have a lightweight renderer
/// in the test target, so this pins the contract at the view source boundary.
final class MixerFXStripGrammarTests: XCTestCase {
    func test_sharedInsertChainRowsAreNameOnlyAndOpenTheEditorSheet() throws {
        let source = try Self.source(named: "Sources/UI/MixerView.swift")
        let row = try XCTUnwrap(Self.functionBody(named: "insertRow", in: source))

        XCTAssertTrue(row.contains("CompactFXInsertButton("))
        XCTAssertTrue(row.contains("title: insert.name"))
        XCTAssertTrue(row.contains("editingInsert = EditingInsert(id: insert.id)"))
        XCTAssertFalse(row.contains("Image(systemName: \"chevron"))
        XCTAssertFalse(row.contains("Circle()"))
        XCTAssertFalse(row.contains("Toggle("))
        XCTAssertFalse(row.contains("removeInsert("))
    }

    func test_sharedEmptyFXSlotIsBarePlusAffordance() throws {
        let source = try Self.source(named: "Sources/UI/MixerView.swift")
        let slot = try XCTUnwrap(Self.propertyBody(named: "emptyInsertSlot", in: source))

        XCTAssertTrue(slot.contains("Image(systemName: \"plus\")"))
        XCTAssertFalse(slot.contains(".studioText(.micro)"))
        XCTAssertTrue(slot.contains(".accessibilityLabel(addLabel)"))
        XCTAssertTrue(slot.contains(".help(addLabel)"))
    }

    func test_sendRowsMatchNameOnlyGrammarAndEditorKeepsControls() throws {
        let source = try Self.source(named: "Sources/UI/Mixer/MixerWorkspaceView.swift")
        let row = try XCTUnwrap(Self.functionBody(named: "sendInsertRow", in: source))
        let editor = try XCTUnwrap(Self.functionBody(named: "sendInsertEditorSheet", in: source))

        XCTAssertTrue(row.contains("Text(insert.name)"))
        XCTAssertTrue(row.contains("sendInsertEditorRequest = SendInsertEditorRequest"))
        XCTAssertFalse(row.contains("Image(systemName: \"chevron"))
        XCTAssertFalse(row.contains("Circle()"))
        XCTAssertFalse(row.contains("Toggle("))
        XCTAssertFalse(row.contains("session.removeSendBusInsert"))

        XCTAssertTrue(editor.contains("FXInsertEditorSheet"))
        XCTAssertTrue(editor.contains("isEnabled:"))
        XCTAssertTrue(editor.contains("wet:"))
        XCTAssertTrue(editor.contains("onMove:"))
        XCTAssertTrue(editor.contains("onRemove:"))
        XCTAssertTrue(editor.contains("session.removeSendBusInsert"))
    }

    func test_compactFXRowsClaimTheWholeTileHitArea() throws {
        let source = try Self.source(named: "Sources/UI/FX/InsertChainComponents.swift")
        let button = try XCTUnwrap(Self.body(after: "struct CompactFXInsertButton", in: source))
        let selectableRow = try XCTUnwrap(Self.body(after: "struct SelectableRowModifier", in: source))

        XCTAssertTrue(button.contains("Button(action: action)"))
        XCTAssertGreaterThanOrEqual(button.components(separatedBy: ".frame(maxWidth: .infinity").count - 1, 2)
        XCTAssertGreaterThanOrEqual(button.components(separatedBy: ".contentShape(rowShape)").count - 1, 2)
        XCTAssertTrue(selectableRow.contains(".contentShape(RoundedRectangle"))
        XCTAssertTrue(selectableRow.contains(".onTapGesture { onSelect?() }"))
    }

    func test_fxEditorUsesCanonicalIconRemoveControl() throws {
        let source = try Self.source(named: "Sources/UI/FX/FXInsertEditorSheet.swift")
        let footer = try XCTUnwrap(Self.propertyBody(named: "footerActions", in: source))

        XCTAssertTrue(footer.contains("StudioCircleIconButton("))
        XCTAssertTrue(footer.contains("systemName: \"xmark\""))
        XCTAssertTrue(footer.contains("help: \"Remove insert\""))
        XCTAssertFalse(footer.contains("Label(\"Remove\""))
        XCTAssertFalse(footer.contains("systemImage: \"trash\""))
    }

    func test_fxEditorModalKeepsLongTitlesFromPushingOutControls() throws {
        let modal = try Self.source(named: "Sources/UI/Theme/StudioModal.swift")
        let header = try XCTUnwrap(Self.body(after: "private var header", in: modal))
        let fxSheet = try Self.source(named: "Sources/UI/FX/FXInsertEditorSheet.swift")

        XCTAssertTrue(header.contains(".lineLimit(1)"))
        XCTAssertTrue(header.contains(".truncationMode(.tail)"))
        XCTAssertTrue(header.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(header.contains("headerAccessory") && header.contains(".fixedSize()"))
        XCTAssertTrue(header.contains("StudioModalCloseButton(action: onClose)") && header.contains(".fixedSize()"))
        XCTAssertTrue(
            fxSheet.contains("minWidth: 560"),
            "The shared FX editor needs enough width for AU names while the title still truncates before controls."
        )
    }

    private static func source(named relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func functionBody(named name: String, in source: String) -> String? {
        body(after: "func \(name)", in: source)
    }

    private static func propertyBody(named name: String, in source: String) -> String? {
        body(after: "var \(name)", in: source)
    }

    private static func body(after marker: String, in source: String) -> String? {
        guard let markerRange = source.range(of: marker),
              let openBrace = source[markerRange.lowerBound...].firstIndex(of: "{")
        else { return nil }

        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openBrace...index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
