import AppKit
import Foundation

@MainActor
protocol EngineLifecycleControlling: AnyObject {
    func shutdown()
}

@MainActor
final class SequencerAIAppDelegate: NSObject, NSApplicationDelegate {
    weak var engineController: (any EngineLifecycleControlling)?
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
        engineController?.shutdown()
        drainRunLoop(shutdownDrainInterval)
        log("applicationWillTerminate complete")
    }
}
