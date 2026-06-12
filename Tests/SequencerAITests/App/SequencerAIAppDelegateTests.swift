import AppKit
import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class SequencerAIAppDelegateTests: XCTestCase {
    func test_buildIdentity_summarizesStampedMetadata() {
        let identity = BuildIdentity(
            version: "0.0.1",
            bundleBuild: "1",
            gitCommit: "4ae5889",
            gitBranch: "main",
            gitDirty: "dirty",
            attributionID: "4ae5889-dirty-20260606224559",
            attributionVersion: "20260606224559"
        )

        XCTAssertEqual(identity.compactDisplay, "main 4ae5889 dirty 20260606224559")
        XCTAssertEqual(
            identity.logSummary,
            "version=0.0.1 build=1 gitCommit=4ae5889 gitBranch=main gitDirty=dirty attributionID=4ae5889-dirty-20260606224559 attributionVersion=20260606224559"
        )
    }

    func test_buildIdentity_replacesUnstampedPlaceholdersWithUnknown() {
        let identity = BuildIdentity(
            version: " $(MARKETING_VERSION) ",
            bundleBuild: "",
            gitCommit: "$(GIT_COMMIT)",
            gitBranch: "$(GIT_BRANCH)",
            gitDirty: "$(GIT_DIRTY)",
            attributionID: "$(BUILD_ATTRIBUTION_ID)",
            attributionVersion: "$(BUILD_ATTRIBUTION_VERSION)"
        )

        XCTAssertEqual(identity.compactDisplay, "unknown")
        XCTAssertEqual(
            identity.logSummary,
            "version=unknown build=unknown gitCommit=unknown gitBranch=unknown gitDirty=unknown attributionID=unknown attributionVersion=unknown"
        )
    }

    func test_buildIdentity_compactDisplayOmitsUnknownFields() {
        // Partially stamped builds (branch + commit known, dirty/attribution
        // unstamped) must not leak "unknown unknown" into the top-bar pill.
        let identity = BuildIdentity(
            gitCommit: "21b2b9c2",
            gitBranch: "main"
        )

        XCTAssertEqual(identity.compactDisplay, "main 21b2b9c2")
        XCTAssertEqual(
            identity.logSummary,
            "version=unknown build=unknown gitCommit=21b2b9c2 gitBranch=main gitDirty=unknown attributionID=unknown attributionVersion=unknown"
        )
    }

    func test_applicationWillTerminate_closesWindows_then_shutsDownEngines_then_drainsRunLoop() {
        let delegate = SequencerAIAppDelegate()
        let windowHost = CapturingWindowHost()
        var events: [String] = []

        windowHost.onCloseAll = { events.append("windows") }
        delegate.drainRunLoop = { _ in events.append("drain") }
        delegate.windowHost = windowHost
        delegate.shutdownDrainInterval = 0.05

        // Register a session with a spy engine so we can observe the shutdown call.
        let box = DocumentBox()
        let spyEngine = EngineController(client: nil, endpoint: nil)
        spyEngine.shutdownObserver = { events.append("engine") }
        let session = SequencerDocumentSession(document: box.binding, engineController: spyEngine)

        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        XCTAssertEqual(events, ["windows", "engine", "drain"])

        // Cleanup registry so this test does not leak into others.
        SequencerDocumentSessionRegistry.unregister(session)
    }
}

@MainActor
private final class CapturingWindowHost: AUWindowHosting {
    var onCloseAll: (() -> Void)?

    func closeAll() {
        onCloseAll?()
    }
}

@MainActor
private final class DocumentBox {
    var document: SeqAIDocument = SeqAIDocument()

    var binding: Binding<SeqAIDocument> {
        Binding(
            get: { self.document },
            set: { self.document = $0 }
        )
    }
}
