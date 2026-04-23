import Foundation

@MainActor
enum SequencerDocumentSessionRegistry {
    private static var entries: [ObjectIdentifier: WeakBox] = [:]

    static func register(_ session: SequencerDocumentSession) {
        prune()
        entries[ObjectIdentifier(session)] = WeakBox(value: session)
    }

    static func unregister(_ session: SequencerDocumentSession) {
        entries.removeValue(forKey: ObjectIdentifier(session))
        prune()
    }

    static func unregister(identifier: ObjectIdentifier) {
        entries.removeValue(forKey: identifier)
        prune()
    }

    static func flushAll() {
        prune()
        for box in entries.values {
            box.value?.flushToDocument()
        }
    }

    /// Calls `shutdown()` on every registered session's engine.
    /// Used by `SequencerAIAppDelegate.applicationWillTerminate` in place of the
    /// former singleton `engineController?.shutdown()`.
    static func shutdownAll() {
        prune()
        for box in entries.values {
            box.value?.engineController.shutdown()
        }
    }

    private static func prune() {
        entries = entries.filter { $0.value.value != nil }
    }
}

@MainActor
private final class WeakBox {
    weak var value: SequencerDocumentSession?

    init(value: SequencerDocumentSession) {
        self.value = value
    }
}
