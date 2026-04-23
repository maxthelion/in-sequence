import AppKit
import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class SequencerAIAppDelegateTests: XCTestCase {
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
