import Foundation

enum SeqAIDocumentProjectionRegistry {
    private static let lock = NSLock()
    private static var projects: [UUID: Project] = [:]

    static func store(project: Project, for runtimeID: UUID) {
        lock.lock()
        projects[runtimeID] = project
        lock.unlock()
    }

    static func remove(runtimeID: UUID) {
        lock.lock()
        projects.removeValue(forKey: runtimeID)
        lock.unlock()
    }

    static func projectForWriting(runtimeID: UUID, fallback: Project) -> Project {
        lock.lock()
        let project = projects[runtimeID] ?? fallback
        lock.unlock()
        return project
    }
}

@MainActor
enum SequencerDocumentSessionRegistry {
    private static var flushers: [UUID: () -> Void] = [:]

    static func register(runtimeID: UUID, flush: @escaping () -> Void) {
        flushers[runtimeID] = flush
    }

    static func unregister(runtimeID: UUID) {
        flushers.removeValue(forKey: runtimeID)
    }

    static func flushAll() {
        for flush in flushers.values {
            flush()
        }
    }
}
