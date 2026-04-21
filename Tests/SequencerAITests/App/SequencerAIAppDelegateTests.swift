import AppKit
import XCTest
@testable import SequencerAI

@MainActor
final class SequencerAIAppDelegateTests: XCTestCase {
    func test_applicationWillTerminate_closesWindows_then_shutsDownEngine_then_drainsRunLoop() {
        let delegate = SequencerAIAppDelegate()
        let engine = CapturingEngineLifecycleController()
        let windowHost = CapturingWindowHost()
        var events: [String] = []

        windowHost.onCloseAll = { events.append("windows") }
        engine.onShutdown = { events.append("engine") }
        delegate.drainRunLoop = { _ in events.append("drain") }
        delegate.engineController = engine
        delegate.windowHost = windowHost
        delegate.shutdownDrainInterval = 0.05

        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        XCTAssertEqual(events, ["windows", "engine", "drain"])
    }
}

@MainActor
private final class CapturingEngineLifecycleController: EngineLifecycleControlling {
    var onShutdown: (() -> Void)?

    func shutdown() {
        onShutdown?()
    }
}

@MainActor
private final class CapturingWindowHost: AUWindowHosting {
    var onCloseAll: (() -> Void)?

    func closeAll() {
        onCloseAll?()
    }
}
