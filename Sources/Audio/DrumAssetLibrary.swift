import Foundation
import CryptoKit
import Observation

/// Global library of drum kits and pattern templates, beside the sample
/// library. Factory content is compiled in and always available; user-created
/// assets persist as JSON manifests under `<libraryRoot>/kits/*.json` and
/// `<libraryRoot>/templates/*.json`.
@Observable
final class DrumAssetLibrary {
    /// UUIDv5 namespace used to derive factory asset IDs from stable names.
    /// DO NOT CHANGE — derived IDs are stable across launches. Generated once for this plan.
    private static let namespace: UUID = UUID(uuidString: "3E7D1B6C-8A4F-4C2E-B5D9-0A1F2E3C4B5D")!

    static let shared: DrumAssetLibrary = {
        do {
            let root = try SampleLibraryBootstrap.ensureLibraryInstalled()
            return DrumAssetLibrary(libraryRoot: root)
        } catch {
            NSLog("[DrumAssetLibrary] bootstrap failed: \(error) — user assets will be empty")
            return DrumAssetLibrary(libraryRoot: SampleLibraryBootstrap.applicationSupportSamplesURL)
        }
    }()

    let libraryRoot: URL
    private(set) var userKits: [DrumKit]
    private(set) var userTemplates: [PatternTemplate]
    /// Global step-order presets, persisted as JSON manifests under
    /// `<libraryRoot>/step-order-maps/*.json`. No factory content.
    private(set) var userStepOrderMaps: [StepOrderMap]

    /// Factory + user kits.
    var kits: [DrumKit] {
        Self.factoryKits + userKits
    }

    /// Factory + user templates.
    var templates: [PatternTemplate] {
        Self.factoryTemplates + userTemplates
    }

    init(libraryRoot: URL) {
        self.libraryRoot = libraryRoot
        self.userKits = Self.loadManifests(in: libraryRoot.appendingPathComponent("kits", isDirectory: true))
        self.userTemplates = Self.loadManifests(in: libraryRoot.appendingPathComponent("templates", isDirectory: true))
        self.userStepOrderMaps = Self.loadManifests(in: libraryRoot.appendingPathComponent("step-order-maps", isDirectory: true))
    }

    func reload() {
        userKits = Self.loadManifests(in: libraryRoot.appendingPathComponent("kits", isDirectory: true))
        userTemplates = Self.loadManifests(in: libraryRoot.appendingPathComponent("templates", isDirectory: true))
        userStepOrderMaps = Self.loadManifests(in: libraryRoot.appendingPathComponent("step-order-maps", isDirectory: true))
    }

    // MARK: - Queries

    func kit(id: UUID) -> DrumKit? {
        kits.first(where: { $0.id == id })
    }

    func template(id: UUID) -> PatternTemplate? {
        templates.first(where: { $0.id == id })
    }

    func stepOrderMap(id: StepOrderMapID) -> StepOrderMap? {
        userStepOrderMaps.first(where: { $0.id == id })
    }

    // MARK: - Factory content

    static let factoryKits: [DrumKit] = [
        DrumKit(
            id: factoryID(name: "kit/808"),
            name: "808",
            parts: [
                DrumKit.Part(tag: "kick", trackName: "Kick"),
                DrumKit.Part(tag: "snare", trackName: "Snare"),
                DrumKit.Part(tag: "hat-closed", trackName: "Hat"),
                DrumKit.Part(tag: "clap", trackName: "Clap"),
            ]
        ),
        DrumKit(
            id: factoryID(name: "kit/acoustic"),
            name: "Acoustic",
            parts: [
                DrumKit.Part(tag: "kick", trackName: "Kick"),
                DrumKit.Part(tag: "snare", trackName: "Snare"),
                DrumKit.Part(tag: "hat-closed", trackName: "Hat"),
            ]
        ),
        DrumKit(
            id: factoryID(name: "kit/techno"),
            name: "Techno",
            parts: [
                DrumKit.Part(tag: "kick", trackName: "Kick"),
                DrumKit.Part(tag: "snare", trackName: "Snare"),
                DrumKit.Part(tag: "hat-closed", trackName: "Hat"),
                DrumKit.Part(tag: "ride", trackName: "Ride"),
            ]
        ),
    ]

    static let factoryTemplates: [PatternTemplate] = [
        PatternTemplate(
            id: factoryID(name: "template/808"),
            name: "808",
            patterns: [
                "kick": [true, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false],
                "snare": [false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false],
                "hat-closed": [true, false, true, false, true, false, true, false, true, false, true, false, true, false, true, false],
                "clap": [false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false],
            ]
        ),
        PatternTemplate(
            id: factoryID(name: "template/acoustic"),
            name: "Acoustic",
            patterns: [
                "kick": [true, false, false, false, false, false, true, false, true, false, false, false, false, false, true, false],
                "snare": [false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false],
                "hat-closed": [true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true],
            ]
        ),
        PatternTemplate(
            id: factoryID(name: "template/techno"),
            name: "Techno",
            patterns: [
                "kick": [true, false, false, false, true, false, false, false, true, false, false, false, true, false, true, false],
                "snare": [false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false],
                "hat-closed": [false, true, false, true, false, true, false, true, false, true, false, true, false, true, false, true],
                "ride": [false, false, false, true, false, false, false, true, false, false, false, true, false, false, false, true],
            ]
        ),
    ]

    // MARK: - Scan

    private static func loadManifests<Asset: Decodable>(in directory: URL) -> [Asset] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let manifests = files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        var assets: [Asset] = []
        for fileURL in manifests {
            do {
                let data = try Data(contentsOf: fileURL)
                assets.append(try decoder.decode(Asset.self, from: data))
            } catch {
                NSLog("[DrumAssetLibrary] skipping unreadable manifest \(fileURL.lastPathComponent): \(error)")
            }
        }
        return assets
    }

    private static func factoryID(name: String) -> UUID {
        uuidV5(namespace: namespace, name: name)
    }

    private static func uuidV5(namespace: UUID, name: String) -> UUID {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: namespace.uuid) { buf in bytes.append(contentsOf: buf) }
        bytes.append(contentsOf: Array(name.utf8))
        let digest = Insecure.SHA1.hash(data: bytes)
        var out = Array(digest.prefix(16))
        out[6] = (out[6] & 0x0F) | 0x50
        out[8] = (out[8] & 0x3F) | 0x80
        return UUID(uuid: (
            out[0], out[1], out[2], out[3],
            out[4], out[5], out[6], out[7],
            out[8], out[9], out[10], out[11],
            out[12], out[13], out[14], out[15]
        ))
    }
}
