import Foundation

struct AudioDevicePreference: Codable, Equatable, Sendable {
    var preferredInputDeviceUID: String?
    var preferredOutputDeviceUID: String?

    static let empty = AudioDevicePreference(
        preferredInputDeviceUID: nil,
        preferredOutputDeviceUID: nil
    )
}

final class AudioDevicePreferenceStore {
    static let shared = AudioDevicePreferenceStore(preferenceURL: {
        let root = try? AppSupportBootstrap.appSupportRoot()
        return (root ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("audio-device.json")
    }())

    private let preferenceURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let lock = NSLock()

    init(preferenceURL: URL, fileManager: FileManager = .default) {
        self.preferenceURL = preferenceURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AudioDevicePreference {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: preferenceURL.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: preferenceURL)
            return try decoder.decode(AudioDevicePreference.self, from: data)
        } catch {
            assertionFailure("AudioDevicePreferenceStore load failed: \(error)")
            NSLog("AudioDevicePreferenceStore load failed: \(error)")
            return .empty
        }
    }

    func save(_ preference: AudioDevicePreference) throws {
        lock.lock()
        defer { lock.unlock() }

        let parent = preferenceURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try encoder.encode(preference)
        let tempURL = parent.appendingPathComponent(UUID().uuidString).appendingPathExtension("tmp")
        try data.write(to: tempURL, options: .atomic)
        if fileManager.fileExists(atPath: preferenceURL.path) {
            try fileManager.removeItem(at: preferenceURL)
        }
        try fileManager.moveItem(at: tempURL, to: preferenceURL)
    }
}
