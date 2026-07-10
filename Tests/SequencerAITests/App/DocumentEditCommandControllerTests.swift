import XCTest
@testable import SequencerAI

@MainActor
final class DocumentEditCommandControllerTests: XCTestCase {
    private let stepsDomain: DocumentEditCommandController.Domain = "steps"
    private let tracksDomain: DocumentEditCommandController.Domain = "tracks"

    func testAvailabilityReflectsActiveTargetImmediately() {
        let controller = DocumentEditCommandController()
        var hasSelection = false

        XCTAssertEqual(controller.availability, .unavailable)

        controller.register(target: makeTarget(
            canCopy: { hasSelection },
            canClear: { hasSelection }
        ))

        XCTAssertEqual(
            controller.availability,
            .init(canCopy: false, canPaste: false, canClear: false)
        )

        hasSelection = true

        XCTAssertEqual(
            controller.availability,
            .init(canCopy: true, canPaste: false, canClear: true)
        )
    }

    func testCompatiblePayloadEnablesAndExecutesPaste() throws {
        let controller = DocumentEditCommandController()
        var pastedSteps: [Int]?

        controller.register(target: makeTarget(
            copy: { [stepsDomain] in
                .init(domain: stepsDomain, snapshot: [1, 3, 5])
            }
        ))
        XCTAssertTrue(controller.copy())

        controller.register(target: makeTarget(
            compatibleDomain: stepsDomain,
            paste: { payload in
                pastedSteps = payload.value(as: [Int].self)
            }
        ))

        XCTAssertTrue(controller.availability.canPaste)
        XCTAssertTrue(controller.paste())
        XCTAssertEqual(pastedSteps, [1, 3, 5])
        XCTAssertEqual(controller.clipboardPayload?.domain, stepsDomain)
    }

    func testIncompatiblePayloadDisablesAndDoesNotExecutePaste() {
        let controller = DocumentEditCommandController()
        var pasteCount = 0

        controller.register(target: makeTarget(
            copy: { [stepsDomain] in
                .init(domain: stepsDomain, snapshot: [1, 2])
            }
        ))
        XCTAssertTrue(controller.copy())

        controller.register(target: makeTarget(
            compatibleDomain: tracksDomain,
            paste: { _ in pasteCount += 1 }
        ))

        XCTAssertFalse(controller.availability.canPaste)
        XCTAssertFalse(controller.paste())
        XCTAssertEqual(pasteCount, 0)
    }

    func testReplacementRoutesCommandsOnlyToNewestTarget() {
        let controller = DocumentEditCommandController()
        var firstCopyCount = 0
        var secondCopyCount = 0

        controller.register(target: makeTarget(copy: { [stepsDomain] in
            firstCopyCount += 1
            return .init(domain: stepsDomain, snapshot: "first")
        }))
        controller.register(target: makeTarget(copy: { [tracksDomain] in
            secondCopyCount += 1
            return .init(domain: tracksDomain, snapshot: "second")
        }))

        XCTAssertTrue(controller.copy())
        XCTAssertEqual(firstCopyCount, 0)
        XCTAssertEqual(secondCopyCount, 1)
        XCTAssertEqual(controller.clipboardPayload?.domain, tracksDomain)
    }

    func testStaleOwnerCannotUpdateOrUnregisterReplacement() {
        let controller = DocumentEditCommandController()
        let staleToken = controller.register(target: makeTarget(canCopy: { false }))
        let currentToken = controller.register(target: makeTarget(canCopy: { true }))

        XCTAssertFalse(controller.update(
            target: makeTarget(canCopy: { false }),
            ownership: staleToken
        ))
        XCTAssertFalse(controller.unregister(ownership: staleToken))
        XCTAssertTrue(controller.availability.canCopy)

        XCTAssertTrue(controller.unregister(ownership: currentToken))
        XCTAssertEqual(controller.availability, .unavailable)
    }

    func testCopyPasteAndClearExecuteTheirSuppliedClosures() {
        let controller = DocumentEditCommandController()
        var hasSelection = true
        var copiedValue = 0
        var pastedValue: Int?
        var clearCount = 0

        controller.register(target: makeTarget(
            canCopy: { hasSelection },
            canClear: { hasSelection },
            compatibleDomain: stepsDomain,
            copy: { [stepsDomain] in
                copiedValue += 1
                return .init(domain: stepsDomain, snapshot: 42)
            },
            paste: { payload in
                pastedValue = payload.value(as: Int.self)
            },
            clearSelection: {
                clearCount += 1
                hasSelection = false
            }
        ))

        XCTAssertTrue(controller.copy())
        XCTAssertTrue(controller.paste())
        XCTAssertTrue(controller.clearSelection())
        XCTAssertEqual(copiedValue, 1)
        XCTAssertEqual(pastedValue, 42)
        XCTAssertEqual(clearCount, 1)
        XCTAssertFalse(controller.availability.canCopy)
        XCTAssertFalse(controller.availability.canClear)
    }

    private func makeTarget(
        canCopy: @escaping () -> Bool = { true },
        canClear: @escaping () -> Bool = { false },
        compatibleDomain: DocumentEditCommandController.Domain? = nil,
        copy: @escaping () -> DocumentEditCommandController.ClipboardPayload? = { nil },
        paste: @escaping (DocumentEditCommandController.ClipboardPayload) -> Void = { _ in },
        clearSelection: @escaping () -> Void = {}
    ) -> DocumentEditCommandController.Target {
        .init(
            canCopy: canCopy,
            canClear: canClear,
            isPasteCompatible: { payload in payload.domain == compatibleDomain },
            copy: copy,
            paste: paste,
            clearSelection: clearSelection
        )
    }
}
