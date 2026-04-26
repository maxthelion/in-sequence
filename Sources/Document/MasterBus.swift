import Foundation

struct MasterBusState: Codable, Equatable, Sendable {
    var scenes: [MasterBusScene]
    var activeSceneID: UUID
    var draftScene: MasterBusScene?
    var abSelection: MasterBusABSelection?

    init(
        scenes: [MasterBusScene] = [.clean],
        activeSceneID: UUID = MasterBusScene.cleanID,
        draftScene: MasterBusScene? = nil,
        abSelection: MasterBusABSelection? = nil
    ) {
        self.scenes = scenes
        self.activeSceneID = activeSceneID
        self.draftScene = draftScene
        self.abSelection = abSelection
        normalize()
    }

    static let `default` = MasterBusState()

    var activeScene: MasterBusScene {
        scenes.first(where: { $0.id == activeSceneID }) ?? .clean
    }

    var liveScene: MasterBusScene {
        draftScene ?? activeScene
    }

    var hasUnsavedDraft: Bool {
        guard let draftScene else { return false }
        return draftScene != activeScene
    }

    var sceneA: MasterBusScene? {
        guard let abSelection else { return nil }
        return scene(id: abSelection.sceneAID)
    }

    var sceneB: MasterBusScene? {
        guard let abSelection else { return nil }
        return scene(id: abSelection.sceneBID)
    }

    func scene(id: UUID) -> MasterBusScene? {
        scenes.first(where: { $0.id == id })
    }

    mutating func setActiveScene(id: UUID) {
        guard scenes.contains(where: { $0.id == id }) else { return }
        activeSceneID = id
        draftScene = nil
        normalize()
    }

    mutating func beginDraftIfNeeded() {
        if draftScene == nil {
            draftScene = activeScene
        }
    }

    mutating func setDraft(_ scene: MasterBusScene) {
        draftScene = scene.normalized()
    }

    mutating func updateDraft(_ update: (inout MasterBusScene) -> Void) {
        beginDraftIfNeeded()
        guard var draft = draftScene else { return }
        update(&draft)
        draftScene = draft.normalized()
    }

    mutating func discardDraft() {
        draftScene = nil
    }

    mutating func commitDraft(name: String? = nil) {
        guard var draft = draftScene?.normalized() else { return }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            draft.name = trimmedName
        }
        if let index = scenes.firstIndex(where: { $0.id == activeSceneID }) {
            draft.id = activeSceneID
            scenes[index] = draft
        } else {
            activeSceneID = draft.id
            scenes.append(draft)
        }
        draftScene = nil
        normalize()
    }

    mutating func saveDraftAsNewScene(name: String) {
        guard var draft = draftScene?.normalized() else { return }
        draft.id = UUID()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.name = trimmed.isEmpty ? "Scene \(scenes.count + 1)" : trimmed
        scenes.append(draft)
        activeSceneID = draft.id
        draftScene = nil
        normalize()
    }

    mutating func addInsert(_ insert: MasterBusInsert) {
        updateDraft { scene in
            scene.inserts.append(insert.normalized())
        }
    }

    mutating func updateInsert(id: UUID, _ update: (inout MasterBusInsert) -> Void) {
        updateDraft { scene in
            guard let index = scene.inserts.firstIndex(where: { $0.id == id }) else {
                return
            }
            update(&scene.inserts[index])
        }
    }

    mutating func removeInsert(id: UUID) {
        updateDraft { scene in
            scene.inserts.removeAll { $0.id == id }
        }
    }

    mutating func reorderInserts(ids: [UUID]) {
        updateDraft { scene in
            let byID = Dictionary(uniqueKeysWithValues: scene.inserts.map { ($0.id, $0) })
            let ordered = ids.compactMap { byID[$0] }
            let missing = scene.inserts.filter { !ids.contains($0.id) }
            scene.inserts = ordered + missing
        }
    }

    mutating func setABSelection(_ selection: MasterBusABSelection?) {
        abSelection = selection
        normalize()
    }

    mutating func setCrossfader(_ value: Double) {
        guard var selection = abSelection else { return }
        selection.crossfader = value.clamped(to: 0...1)
        abSelection = selection
    }

    mutating func normalize() {
        if scenes.isEmpty {
            scenes = [.clean]
        }

        var seenSceneIDs = Set<UUID>()
        scenes = scenes.map { scene in
            var normalized = scene.normalized()
            if seenSceneIDs.contains(normalized.id) {
                normalized.id = UUID()
            }
            seenSceneIDs.insert(normalized.id)
            return normalized
        }

        if !scenes.contains(where: { $0.id == activeSceneID }) {
            activeSceneID = scenes[0].id
        }

        draftScene = draftScene?.normalized()

        if let selection = abSelection?.normalized(),
           scenes.contains(where: { $0.id == selection.sceneAID }),
           scenes.contains(where: { $0.id == selection.sceneBID })
        {
            abSelection = selection
        } else {
            abSelection = nil
        }
    }

    func normalized() -> MasterBusState {
        var copy = self
        copy.normalize()
        return copy
    }
}

struct MasterBusScene: Codable, Equatable, Identifiable, Sendable {
    static let cleanID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let clean = MasterBusScene(id: cleanID, name: "Clean", inserts: [], outputGain: 1)

    var id: UUID
    var name: String
    var inserts: [MasterBusInsert]
    var outputGain: Double

    init(
        id: UUID = UUID(),
        name: String,
        inserts: [MasterBusInsert] = [],
        outputGain: Double = 1
    ) {
        self.id = id
        self.name = name
        self.inserts = inserts
        self.outputGain = outputGain
    }

    func normalized() -> MasterBusScene {
        var copy = self
        let trimmed = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmed.isEmpty ? "Scene" : trimmed
        copy.outputGain = copy.outputGain.clamped(to: 0...1.5)
        copy.inserts = copy.inserts.map { $0.normalized() }
        return copy
    }
}

struct MasterBusABSelection: Codable, Equatable, Sendable {
    var sceneAID: UUID
    var sceneBID: UUID
    var crossfader: Double

    init(sceneAID: UUID, sceneBID: UUID, crossfader: Double = 0) {
        self.sceneAID = sceneAID
        self.sceneBID = sceneBID
        self.crossfader = crossfader.clamped(to: 0...1)
    }

    func normalized() -> MasterBusABSelection {
        MasterBusABSelection(sceneAID: sceneAID, sceneBID: sceneBID, crossfader: crossfader)
    }
}

struct MasterBusInsert: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var wetDry: Double
    var kind: MasterBusInsertKind

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        wetDry: Double = 1,
        kind: MasterBusInsertKind
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.wetDry = wetDry
        self.kind = kind
    }

    static func filter() -> MasterBusInsert {
        MasterBusInsert(name: "Filter", kind: .nativeFilter(.default))
    }

    static func bitcrusher() -> MasterBusInsert {
        MasterBusInsert(name: "Bitcrusher", kind: .nativeBitcrusher(.default))
    }

    static func auEffect(_ choice: AudioEffectChoice) -> MasterBusInsert {
        MasterBusInsert(
            name: choice.displayName,
            kind: .auEffect(componentID: choice.audioComponentID, stateBlob: nil)
        )
    }

    func normalized() -> MasterBusInsert {
        var copy = self
        let trimmed = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmed.isEmpty ? copy.kind.defaultName : trimmed
        copy.wetDry = copy.wetDry.clamped(to: 0...1)
        copy.kind = copy.kind.normalized()
        return copy
    }
}

enum MasterBusInsertKind: Codable, Equatable, Sendable {
    case nativeFilter(MasterFilterSettings)
    case nativeBitcrusher(MasterBitcrusherSettings)
    case auEffect(componentID: AudioComponentID, stateBlob: Data?)

    var defaultName: String {
        switch self {
        case .nativeFilter:
            return "Filter"
        case .nativeBitcrusher:
            return "Bitcrusher"
        case .auEffect:
            return "AU Effect"
        }
    }

    var summary: String {
        switch self {
        case let .nativeFilter(settings):
            return "\(Int(settings.cutoffHz.rounded())) Hz"
        case let .nativeBitcrusher(settings):
            return "\(settings.bitDepth)-bit"
        case let .auEffect(componentID, _):
            return componentID.displayKey
        }
    }

    func normalized() -> MasterBusInsertKind {
        switch self {
        case let .nativeFilter(settings):
            return .nativeFilter(settings.normalized())
        case let .nativeBitcrusher(settings):
            return .nativeBitcrusher(settings.normalized())
        case .auEffect:
            return self
        }
    }
}

struct MasterFilterSettings: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case lowPass
        case highPass
    }

    var mode: Mode
    var cutoffHz: Double
    var resonance: Double

    static let `default` = MasterFilterSettings(mode: .lowPass, cutoffHz: 12_000, resonance: 0.2)

    func normalized() -> MasterFilterSettings {
        MasterFilterSettings(
            mode: mode,
            cutoffHz: cutoffHz.clamped(to: 20...20_000),
            resonance: resonance.clamped(to: 0...1)
        )
    }
}

struct MasterBitcrusherSettings: Codable, Equatable, Sendable {
    var bitDepth: Int
    var sampleRateScale: Double
    var drive: Double

    static let `default` = MasterBitcrusherSettings(bitDepth: 12, sampleRateScale: 0.5, drive: 0)

    func normalized() -> MasterBitcrusherSettings {
        MasterBitcrusherSettings(
            bitDepth: Int(Double(bitDepth).clamped(to: 4...16)),
            sampleRateScale: sampleRateScale.clamped(to: 0.05...1),
            drive: drive.clamped(to: 0...1)
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
