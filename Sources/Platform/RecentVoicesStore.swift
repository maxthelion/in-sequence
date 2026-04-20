import Foundation

struct RecentVoice: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var destination: Destination
    var firstSeen: Date
    var lastUsed: Date
    var projectOrigin: String?

    init(
        id: UUID = UUID(),
        name: String,
        destination: Destination,
        firstSeen: Date = Date(),
        lastUsed: Date = Date(),
        projectOrigin: String? = nil
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.firstSeen = firstSeen
        self.lastUsed = lastUsed
        self.projectOrigin = projectOrigin
    }
}

final class RecentVoicesStore {
    static let shared = RecentVoicesStore(historyURL: {
        let root = try? AppSupportBootstrap.appSupportRoot()
        return (root ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("voices/history.json")
    }())

    private let historyURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let lock = NSLock()

    init(historyURL: URL, fileManager: FileManager = .default) {
        self.historyURL = historyURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> [RecentVoice] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    func record(_ voice: RecentVoice) {
        lock.lock()
        defer { lock.unlock() }

        var voices = loadUnlocked()
        if let index = voices.firstIndex(where: { $0.id == voice.id }) {
            voices[index].name = voice.name
            voices[index].destination = voice.destination
            voices[index].lastUsed = max(voices[index].lastUsed, voice.lastUsed)
            voices[index].projectOrigin = voice.projectOrigin ?? voices[index].projectOrigin
        } else {
            voices.append(voice)
        }
        saveUnlocked(voices)
    }

    func touch(id: UUID) {
        lock.lock()
        defer { lock.unlock() }

        var voices = loadUnlocked()
        guard let index = voices.firstIndex(where: { $0.id == id }) else {
            return
        }
        voices[index].lastUsed = Date()
        saveUnlocked(voices)
    }

    func rename(id: UUID, to name: String) {
        lock.lock()
        defer { lock.unlock() }

        var voices = loadUnlocked()
        guard let index = voices.firstIndex(where: { $0.id == id }) else {
            return
        }
        voices[index].name = name
        saveUnlocked(voices)
    }

    func prune(maxEntries: Int = 64) {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = Array(loadUnlocked().prefix(maxEntries))
        saveUnlocked(trimmed)
    }

    private func loadUnlocked() -> [RecentVoice] {
        guard fileManager.fileExists(atPath: historyURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: historyURL)
            let decoded = try decoder.decode([RecentVoice].self, from: data)
            return decoded.sorted { lhs, rhs in
                if lhs.lastUsed == rhs.lastUsed {
                    return lhs.firstSeen > rhs.firstSeen
                }
                return lhs.lastUsed > rhs.lastUsed
            }
        } catch {
            assertionFailure("RecentVoicesStore load failed: \(error)")
            NSLog("RecentVoicesStore load failed: \(error)")
            return []
        }
    }

    private func saveUnlocked(_ voices: [RecentVoice]) {
        let sorted = voices.sorted { lhs, rhs in
            if lhs.lastUsed == rhs.lastUsed {
                return lhs.firstSeen > rhs.firstSeen
            }
            return lhs.lastUsed > rhs.lastUsed
        }

        do {
            let parent = historyURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let data = try encoder.encode(sorted)
            let tempURL = parent.appendingPathComponent(UUID().uuidString).appendingPathExtension("tmp")
            try data.write(to: tempURL, options: .atomic)
            if fileManager.fileExists(atPath: historyURL.path) {
                try fileManager.removeItem(at: historyURL)
            }
            try fileManager.moveItem(at: tempURL, to: historyURL)
        } catch {
            NSLog("RecentVoicesStore save failed: \(error)")
        }
    }
}
