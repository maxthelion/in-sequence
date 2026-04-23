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

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Start warming the AU component cache on a background queue.
        // This fires before SwiftUI begins constructing App/Scene/View objects, so by the
        // time AudioInstrumentHost.init evaluates AudioInstrumentChoice.defaultChoices the
        // scan is either already done (fast machines) or in-flight (slow machines; the first
        // actual read will block only until the background task finishes, not for a full
        // duplicate scan).
        NSLog("[U2] SequencerAIAppDelegate: beginWarmingIfNeeded")
        AudioInstrumentChoiceCache.shared.beginWarmingIfNeeded()
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
