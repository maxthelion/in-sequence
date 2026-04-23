import AppKit
import Foundation

@MainActor
protocol EngineLifecycleControlling: AnyObject {
    func shutdown()
}

@MainActor
final class SequencerAIAppDelegate: NSObject, NSApplicationDelegate {
    var windowHost: any AUWindowHosting = AUWindowHost.shared
    var shutdownDrainInterval: TimeInterval = 0.15
    var drainRunLoop: (TimeInterval) -> Void = { interval in
        guard interval > 0 else {
            return
        }
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    private func log(_ message: String) {
        NSLog("[SequencerAIAppDelegate] \(message)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        log("applicationWillTerminate start")
        SequencerDocumentSessionRegistry.flushAll()
        windowHost.closeAll()
        SequencerDocumentSessionRegistry.shutdownAll()
        drainRunLoop(shutdownDrainInterval)
        log("applicationWillTerminate complete")
    }

    func applicationDidResignActive(_ notification: Notification) {
        log("applicationDidResignActive: flushing all sessions")
        SequencerDocumentSessionRegistry.flushAll()
    }
}
