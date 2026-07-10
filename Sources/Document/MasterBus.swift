import Foundation

struct MasterBusState: Codable, Equatable, Sendable {
    static let masterOutputGainRange: ClosedRange<Double> = 0...2

    var scenes: [MasterBusScene]
    var activeSceneID: UUID
    var abSelection: MasterBusABSelection?
    var masterOutputGain: Double
    var masterInserts: [MasterBusInsert]

    init(
        scenes: [MasterBusScene]? = nil,
        activeSceneID: UUID? = nil,
        abSelection: MasterBusABSelection? = nil,
        masterOutputGain: Double = 1,
        masterInserts: [MasterBusInsert] = []
    ) {
        let resolvedScenes = scenes ?? [.sceneA, .sceneB]
        self.scenes = resolvedScenes
        self.activeSceneID = activeSceneID ?? resolvedScenes.first?.id ?? MasterBusScene.sceneAID
        self.abSelection = abSelection
        self.masterOutputGain = masterOutputGain
        self.masterInserts = masterInserts
        normalize()
    }

    static let `default` = MasterBusState()

    var activeScene: MasterBusScene {
        scenes.first(where: { $0.id == activeSceneID }) ?? .sceneA
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

    @discardableResult
    mutating func addScene(name: String? = nil, copyFrom sourceSceneID: UUID? = nil) -> UUID {
        let sourceScene = sourceSceneID.flatMap { self.scene(id: $0) }
        var newScene = sourceScene?.duplicatedForNewScene() ?? MasterBusScene(name: resolvedNewSceneName())
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            newScene.name = trimmed.isEmpty ? resolvedNewSceneName() : trimmed
        } else if sourceScene != nil {
            newScene.name = resolvedNewSceneName(base: "\(newScene.name) Copy")
        }
        scenes.append(newScene.normalized())
        activeSceneID = newScene.id
        normalize()
        return newScene.id
    }

    /// Inserts a detached scene snapshot without changing playback or A/B state.
    @discardableResult
    mutating func insertSceneCopy(of snapshot: MasterBusScene) -> UUID {
        var newScene = snapshot.duplicatedForNewScene()
        newScene.name = resolvedNewSceneName(base: "\(snapshot.name) Copy")
        scenes.append(newScene.normalized())
        normalize()
        return newScene.id
    }

    mutating func removeScene(id: UUID) {
        guard scenes.count > 2 else { return }
        scenes.removeAll { $0.id == id }
        if activeSceneID == id {
            activeSceneID = scenes.first?.id ?? MasterBusScene.sceneAID
        }
        if abSelection?.sceneAID == id || abSelection?.sceneBID == id {
            abSelection = nil
        }
        normalize()
    }

    mutating func setActiveScene(id: UUID) {
        guard scenes.contains(where: { $0.id == id }) else { return }
        activeSceneID = id
        normalize()
    }

    mutating func updateScene(id: UUID, _ update: (inout MasterBusScene) -> Void) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else {
            return
        }
        update(&scenes[index])
        scenes[index] = scenes[index].normalized()
        normalize()
    }

    mutating func addInsert(_ insert: MasterBusInsert, sceneID: UUID? = nil) {
        updateScene(id: sceneID ?? activeSceneID) { scene in
            scene.inserts.append(insert.normalized())
        }
    }

    mutating func updateInsert(id: UUID, sceneID: UUID? = nil, _ update: (inout MasterBusInsert) -> Void) {
        updateScene(id: sceneID ?? activeSceneID) { scene in
            guard let index = scene.inserts.firstIndex(where: { $0.id == id }) else {
                return
            }
            update(&scene.inserts[index])
        }
    }

    mutating func removeInsert(id: UUID, sceneID: UUID? = nil) {
        updateScene(id: sceneID ?? activeSceneID) { scene in
            scene.inserts.removeAll { $0.id == id }
            scene.macroBindings.removeAll { $0.target.targetsInsert(id) }
        }
    }

    mutating func reorderInserts(ids: [UUID], sceneID: UUID? = nil) {
        updateScene(id: sceneID ?? activeSceneID) { scene in
            let byID = Dictionary(uniqueKeysWithValues: scene.inserts.map { ($0.id, $0) })
            let ordered = ids.compactMap { byID[$0] }
            let missing = scene.inserts.filter { !ids.contains($0.id) }
            scene.inserts = ordered + missing
        }
    }

    mutating func addMasterInsert(_ insert: MasterBusInsert) {
        masterInserts.append(insert.normalized())
        normalize()
    }

    mutating func updateMasterInsert(id: UUID, _ update: (inout MasterBusInsert) -> Void) {
        guard let index = masterInserts.firstIndex(where: { $0.id == id }) else {
            return
        }
        update(&masterInserts[index])
        masterInserts[index] = masterInserts[index].normalized()
        normalize()
    }

    mutating func removeMasterInsert(id: UUID) {
        masterInserts.removeAll { $0.id == id }
        normalize()
    }

    mutating func reorderMasterInserts(ids: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: masterInserts.map { ($0.id, $0) })
        let ordered = ids.compactMap { byID[$0] }
        let missing = masterInserts.filter { !ids.contains($0.id) }
        masterInserts = ordered + missing
        normalize()
    }

    mutating func upsertMacroBinding(_ binding: MasterSceneMacroBinding, sceneID: UUID? = nil) {
        updateScene(id: sceneID ?? activeSceneID) { scene in
            guard binding.target.isValid(in: scene) else { return }
            if let index = scene.macroBindings.firstIndex(where: { $0.id == binding.id }) {
                scene.macroBindings[index] = binding
            } else if scene.macroBindings.count < MasterSceneMacroBinding.slotCount {
                scene.macroBindings.append(binding)
            }
        }
    }

    mutating func removeMacroBinding(id: UUID, sceneID: UUID? = nil) {
        updateScene(id: sceneID ?? activeSceneID) { scene in
            scene.macroBindings.removeAll { $0.id == id }
        }
    }

    mutating func setMacroValue(sceneID: UUID, macroID: UUID, value: Double) {
        updateScene(id: sceneID) { scene in
            guard let index = scene.macroBindings.firstIndex(where: { $0.id == macroID }) else {
                return
            }
            let binding = scene.macroBindings[index]
            if binding.target.storesAuthoredValue {
                scene.macroBindings[index].authoredValue = value.clamped(to: binding.target.valueRange)
            }
            binding.target.write(value, to: &scene)
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

    mutating func setMasterOutputGain(_ value: Double) {
        masterOutputGain = Self.normalizedMasterOutputGain(value)
    }

    mutating func normalize() {
        masterOutputGain = Self.normalizedMasterOutputGain(masterOutputGain)
        masterInserts = Self.normalizedInserts(masterInserts)

        if scenes.isEmpty {
            scenes = [.sceneA, .sceneB]
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

        if scenes.count < 2 {
            var fallback = scenes.first?.id == MasterBusScene.sceneAID ? MasterBusScene.sceneB : MasterBusScene.sceneA
            if scenes.contains(where: { $0.id == fallback.id }) {
                fallback.id = UUID()
            }
            scenes.append(fallback.normalized())
        }

        if !scenes.contains(where: { $0.id == activeSceneID }) {
            activeSceneID = scenes[0].id
        }

        if let selection = abSelection?.normalized(),
           scenes.contains(where: { $0.id == selection.sceneAID }),
           scenes.contains(where: { $0.id == selection.sceneBID }),
           selection.sceneAID != selection.sceneBID
        {
            abSelection = selection
        } else {
            abSelection = MasterBusABSelection(
                sceneAID: scenes[0].id,
                sceneBID: scenes[1].id,
                crossfader: abSelection?.crossfader ?? 0
            )
        }
    }

    func normalized() -> MasterBusState {
        var copy = self
        copy.normalize()
        return copy
    }

    func applyingPerformanceOverlay(_ overlay: MasterBusPerformanceOverlayState) -> MasterBusState {
        var copy = self
        for (sceneID, valuesByMacroID) in overlay.sceneMacroOverrides {
            for (macroID, value) in valuesByMacroID {
                copy.setMacroValue(sceneID: sceneID, macroID: macroID, value: value)
            }
        }
        if let selection = overlay.abSelectionOverride {
            copy.setABSelection(selection)
        }
        if let crossfader = overlay.crossfaderOverride {
            copy.setCrossfader(crossfader)
        }
        return copy.normalized()
    }

    private func resolvedNewSceneName(base: String = "Scene") -> String {
        var candidate = base
        var index = scenes.count + 1
        let existingNames = Set(scenes.map(\.name))
        if !existingNames.contains(candidate) {
            return candidate
        }
        repeat {
            candidate = "\(base) \(index)"
            index += 1
        } while existingNames.contains(candidate)
        return candidate
    }

    private static func normalizedMasterOutputGain(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return value.clamped(to: masterOutputGainRange)
    }

    private static func normalizedInserts(_ inserts: [MasterBusInsert]) -> [MasterBusInsert] {
        var seenIDs = Set<UUID>()
        return inserts.map { insert in
            var normalized = insert.normalized()
            if seenIDs.contains(normalized.id) {
                normalized.id = UUID()
            }
            seenIDs.insert(normalized.id)
            return normalized
        }
    }
}

extension MasterBusState {
    private enum CodingKeys: String, CodingKey {
        case scenes
        case activeSceneID
        case draftScene
        case abSelection
        case masterOutputGain
        case masterInserts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scenes = try container.decodeIfPresent([MasterBusScene].self, forKey: .scenes) ?? [.sceneA, .sceneB]
        activeSceneID = try container.decodeIfPresent(UUID.self, forKey: .activeSceneID)
            ?? scenes.first?.id
            ?? MasterBusScene.sceneAID
        abSelection = try container.decodeIfPresent(MasterBusABSelection.self, forKey: .abSelection)
        masterOutputGain = try container.decodeIfPresent(Double.self, forKey: .masterOutputGain) ?? 1
        masterInserts = try container.decodeIfPresent([MasterBusInsert].self, forKey: .masterInserts) ?? []

        if let draftScene = try container.decodeIfPresent(MasterBusScene.self, forKey: .draftScene) {
            if let index = scenes.firstIndex(where: { $0.id == activeSceneID }) {
                var promoted = draftScene
                promoted.id = activeSceneID
                scenes[index] = promoted
            } else {
                scenes.append(draftScene)
                activeSceneID = draftScene.id
            }
        }

        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scenes, forKey: .scenes)
        try container.encode(activeSceneID, forKey: .activeSceneID)
        try container.encodeIfPresent(abSelection, forKey: .abSelection)
        try container.encode(masterOutputGain, forKey: .masterOutputGain)
        try container.encode(masterInserts, forKey: .masterInserts)
    }
}

struct MasterBusScene: Codable, Equatable, Identifiable, Sendable {
    static let sceneAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let sceneBID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let cleanID = sceneAID
    static let sceneA = MasterBusScene(id: sceneAID, name: "1", inserts: [], outputGain: 1, macroBindings: [])
    static let sceneB = MasterBusScene(id: sceneBID, name: "2", inserts: [], outputGain: 1, macroBindings: [])
    static let clean = sceneA

    var id: UUID
    var name: String
    var inserts: [MasterBusInsert]
    var outputGain: Double
    var macroBindings: [MasterSceneMacroBinding]

    init(
        id: UUID = UUID(),
        name: String,
        inserts: [MasterBusInsert] = [],
        outputGain: Double = 1,
        macroBindings: [MasterSceneMacroBinding] = []
    ) {
        self.id = id
        self.name = name
        self.inserts = inserts
        self.outputGain = outputGain
        self.macroBindings = macroBindings
    }

    func normalized() -> MasterBusScene {
        var copy = self
        let trimmed = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmed.isEmpty ? "Scene" : trimmed
        copy.outputGain = 1
        copy.inserts = copy.inserts.map { $0.normalized() }
        copy.macroBindings = Self.normalizedMacroBindings(copy.macroBindings, in: copy)
        return copy
    }

    func duplicatedForNewScene() -> MasterBusScene {
        var copy = self
        copy.id = UUID()
        var insertIDMap: [UUID: UUID] = [:]
        copy.inserts = inserts.map { insert in
            var duplicated = insert
            let newID = UUID()
            insertIDMap[insert.id] = newID
            duplicated.id = newID
            return duplicated
        }
        copy.macroBindings = macroBindings.map { binding in
            var duplicated = binding
            duplicated.id = UUID()
            duplicated.target = duplicated.target.remappedInsertIDs(insertIDMap)
            return duplicated
        }
        return copy.normalized()
    }

    private static func normalizedMacroBindings(
        _ bindings: [MasterSceneMacroBinding],
        in scene: MasterBusScene
    ) -> [MasterSceneMacroBinding] {
        var occupiedSlots = Set<Int>()
        var seenIDs = Set<UUID>()
        var normalizedBindings: [MasterSceneMacroBinding] = []

        for binding in bindings.sorted(by: { lhs, rhs in
            if lhs.slotIndex == rhs.slotIndex {
                return lhs.name < rhs.name
            }
            return lhs.slotIndex < rhs.slotIndex
        }) {
            guard binding.target.isValid(in: scene) else { continue }
            guard normalizedBindings.count < MasterSceneMacroBinding.slotCount else { break }

            var normalized = binding.normalized(in: scene)
            if seenIDs.contains(normalized.id) {
                normalized.id = UUID()
            }
            guard let slotIndex = availableSlot(preferred: normalized.slotIndex, occupied: occupiedSlots) else {
                continue
            }
            normalized.slotIndex = slotIndex
            seenIDs.insert(normalized.id)
            occupiedSlots.insert(slotIndex)
            normalizedBindings.append(normalized)
        }

        return normalizedBindings.sorted { $0.slotIndex < $1.slotIndex }
    }

    private static func availableSlot(preferred: Int, occupied: Set<Int>) -> Int? {
        if (0..<MasterSceneMacroBinding.slotCount).contains(preferred),
           !occupied.contains(preferred)
        {
            return preferred
        }
        return (0..<MasterSceneMacroBinding.slotCount).first { !occupied.contains($0) }
    }
}

struct MasterSceneMacroBinding: Codable, Equatable, Identifiable, Sendable {
    static let slotCount = 8

    var id: UUID
    var slotIndex: Int
    var name: String
    var target: MasterSceneMacroTarget
    var authoredValue: Double?

    init(
        id: UUID = UUID(),
        slotIndex: Int,
        name: String? = nil,
        target: MasterSceneMacroTarget,
        authoredValue: Double? = nil
    ) {
        self.id = id
        self.slotIndex = slotIndex
        self.name = name ?? ""
        self.target = target
        self.authoredValue = authoredValue
    }

    func normalized(in scene: MasterBusScene) -> MasterSceneMacroBinding {
        var copy = self
        copy.slotIndex = Int(Double(copy.slotIndex).clamped(to: 0...Double(Self.slotCount - 1)))
        let trimmed = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmed.isEmpty ? copy.target.label(in: scene) : trimmed
        if let value = copy.authoredValue {
            copy.authoredValue = value.clamped(to: copy.target.valueRange)
        } else if let defaultValue = copy.target.authoredDefaultValue {
            copy.authoredValue = defaultValue.clamped(to: copy.target.valueRange)
        }
        return copy
    }

    func value(in scene: MasterBusScene) -> Double? {
        target.read(from: scene) ?? authoredValue
    }
}

struct AUParameterReference: Codable, Equatable, Sendable {
    var insertID: UUID
    var address: UInt64
    var identifier: String
    var displayName: String
    var minValue: Double
    var maxValue: Double
    var defaultValue: Double
    var unit: String?

    var valueRange: ClosedRange<Double> {
        let lower = min(minValue, maxValue)
        let upper = max(minValue, maxValue)
        return lower == upper ? (lower...(lower + 1)) : (lower...upper)
    }

    func remappedInsertIDs(_ insertIDMap: [UUID: UUID]) -> AUParameterReference {
        AUParameterReference(
            insertID: insertIDMap[insertID] ?? insertID,
            address: address,
            identifier: identifier,
            displayName: displayName,
            minValue: minValue,
            maxValue: maxValue,
            defaultValue: defaultValue,
            unit: unit
        )
    }
}

enum MasterSceneMacroTarget: Codable, Equatable, Sendable {
    case outputGain
    case insertWetDry(insertID: UUID)
    case filterCutoff(insertID: UUID)
    case filterResonance(insertID: UUID)
    case bitcrusherRate(insertID: UUID)
    case bitcrusherDrive(insertID: UUID)
    case auParameter(
        insertID: UUID,
        address: UInt64,
        identifier: String,
        displayName: String,
        minValue: Double,
        maxValue: Double,
        defaultValue: Double,
        unit: String?
    )

    var valueRange: ClosedRange<Double> {
        switch self {
        case .outputGain:
            return 0...1.5
        case .insertWetDry,
             .filterResonance,
             .bitcrusherRate,
             .bitcrusherDrive:
            return 0...1
        case .filterCutoff:
            return 20...20_000
        case .auParameter:
            return auParameterReference?.valueRange ?? 0...1
        }
    }

    var authoredDefaultValue: Double? {
        switch self {
        case .auParameter:
            return auParameterReference?.defaultValue
        default:
            return nil
        }
    }

    var storesAuthoredValue: Bool {
        authoredDefaultValue != nil
    }

    func isValid(in scene: MasterBusScene) -> Bool {
        switch self {
        case .outputGain:
            return false
        case let .insertWetDry(insertID):
            return scene.inserts.contains { $0.id == insertID }
        case let .filterCutoff(insertID),
             let .filterResonance(insertID):
            return scene.inserts.contains { insert in
                guard insert.id == insertID else { return false }
                if case .nativeFilter = insert.kind { return true }
                return false
            }
        case let .bitcrusherRate(insertID),
             let .bitcrusherDrive(insertID):
            return scene.inserts.contains { insert in
                guard insert.id == insertID else { return false }
                if case .nativeBitcrusher = insert.kind { return true }
                return false
            }
        case let .auParameter(insertID, _, _, _, _, _, _, _):
            return scene.inserts.contains { insert in
                guard insert.id == insertID else { return false }
                if case .auEffect = insert.kind { return true }
                return false
            }
        }
    }

    func targetsInsert(_ insertID: UUID) -> Bool {
        switch self {
        case .outputGain:
            return false
        case let .insertWetDry(id),
             let .filterCutoff(id),
             let .filterResonance(id),
             let .bitcrusherRate(id),
             let .bitcrusherDrive(id),
             let .auParameter(id, _, _, _, _, _, _, _):
            return id == insertID
        }
    }

    func remappedInsertIDs(_ insertIDMap: [UUID: UUID]) -> MasterSceneMacroTarget {
        switch self {
        case .outputGain:
            return self
        case let .insertWetDry(insertID):
            return .insertWetDry(insertID: insertIDMap[insertID] ?? insertID)
        case let .filterCutoff(insertID):
            return .filterCutoff(insertID: insertIDMap[insertID] ?? insertID)
        case let .filterResonance(insertID):
            return .filterResonance(insertID: insertIDMap[insertID] ?? insertID)
        case let .bitcrusherRate(insertID):
            return .bitcrusherRate(insertID: insertIDMap[insertID] ?? insertID)
        case let .bitcrusherDrive(insertID):
            return .bitcrusherDrive(insertID: insertIDMap[insertID] ?? insertID)
        case .auParameter:
            guard let reference = auParameterReference else { return self }
            return Self.auParameter(reference.remappedInsertIDs(insertIDMap))
        }
    }

    func read(from scene: MasterBusScene) -> Double? {
        switch self {
        case .outputGain:
            return nil
        case let .insertWetDry(insertID):
            return scene.inserts.first(where: { $0.id == insertID })?.wetDry
        case let .filterCutoff(insertID):
            guard case let .nativeFilter(settings)? = scene.inserts.first(where: { $0.id == insertID })?.kind else {
                return nil
            }
            return settings.cutoffHz
        case let .filterResonance(insertID):
            guard case let .nativeFilter(settings)? = scene.inserts.first(where: { $0.id == insertID })?.kind else {
                return nil
            }
            return settings.resonance
        case let .bitcrusherRate(insertID):
            guard case let .nativeBitcrusher(settings)? = scene.inserts.first(where: { $0.id == insertID })?.kind else {
                return nil
            }
            return settings.sampleRateScale
        case let .bitcrusherDrive(insertID):
            guard case let .nativeBitcrusher(settings)? = scene.inserts.first(where: { $0.id == insertID })?.kind else {
                return nil
            }
            return settings.drive
        case .auParameter:
            return nil
        }
    }

    func write(_ value: Double, to scene: inout MasterBusScene) {
        let clamped = value.clamped(to: valueRange)
        switch self {
        case .outputGain:
            return
        case let .insertWetDry(insertID):
            guard let index = scene.inserts.firstIndex(where: { $0.id == insertID }) else { return }
            scene.inserts[index].wetDry = clamped
        case let .filterCutoff(insertID):
            updateFilter(insertID: insertID, in: &scene) { $0.cutoffHz = clamped }
        case let .filterResonance(insertID):
            updateFilter(insertID: insertID, in: &scene) { $0.resonance = clamped }
        case let .bitcrusherRate(insertID):
            updateBitcrusher(insertID: insertID, in: &scene) { $0.sampleRateScale = clamped }
        case let .bitcrusherDrive(insertID):
            updateBitcrusher(insertID: insertID, in: &scene) { $0.drive = clamped }
        case .auParameter:
            return
        }
    }

    func label(in scene: MasterBusScene) -> String {
        switch self {
        case .outputGain:
            return "Output Gain"
        case let .insertWetDry(insertID):
            return "\(insertName(insertID, in: scene)) Wet"
        case let .filterCutoff(insertID):
            return "\(insertName(insertID, in: scene)) Cutoff"
        case let .filterResonance(insertID):
            return "\(insertName(insertID, in: scene)) Resonance"
        case let .bitcrusherRate(insertID):
            return "\(insertName(insertID, in: scene)) Rate"
        case let .bitcrusherDrive(insertID):
            return "\(insertName(insertID, in: scene)) Drive"
        case .auParameter:
            guard let reference = auParameterReference else { return "Insert Parameter" }
            return "\(insertName(reference.insertID, in: scene)) \(reference.displayName)"
        }
    }

    private var auParameterReference: AUParameterReference? {
        guard case let .auParameter(insertID, address, identifier, displayName, minValue, maxValue, defaultValue, unit) = self else {
            return nil
        }
        return AUParameterReference(
            insertID: insertID,
            address: address,
            identifier: identifier,
            displayName: displayName,
            minValue: minValue,
            maxValue: maxValue,
            defaultValue: defaultValue,
            unit: unit
        )
    }

    private static func auParameter(_ reference: AUParameterReference) -> MasterSceneMacroTarget {
        .auParameter(
            insertID: reference.insertID,
            address: reference.address,
            identifier: reference.identifier,
            displayName: reference.displayName,
            minValue: reference.minValue,
            maxValue: reference.maxValue,
            defaultValue: reference.defaultValue,
            unit: reference.unit
        )
    }

    private func insertName(_ insertID: UUID, in scene: MasterBusScene) -> String {
        scene.inserts.first(where: { $0.id == insertID })?.name ?? "Insert"
    }

    private func updateFilter(
        insertID: UUID,
        in scene: inout MasterBusScene,
        _ update: (inout MasterFilterSettings) -> Void
    ) {
        guard let index = scene.inserts.firstIndex(where: { $0.id == insertID }),
              case var .nativeFilter(settings) = scene.inserts[index].kind
        else { return }
        update(&settings)
        scene.inserts[index].kind = .nativeFilter(settings)
    }

    private func updateBitcrusher(
        insertID: UUID,
        in scene: inout MasterBusScene,
        _ update: (inout MasterBitcrusherSettings) -> Void
    ) {
        guard let index = scene.inserts.firstIndex(where: { $0.id == insertID }),
              case var .nativeBitcrusher(settings) = scene.inserts[index].kind
        else { return }
        update(&settings)
        scene.inserts[index].kind = .nativeBitcrusher(settings)
    }
}

struct MasterBusPerformanceOverlayState: Equatable, Sendable {
    var sceneMacroOverrides: [UUID: [UUID: Double]] = [:]
    var abSelectionOverride: MasterBusABSelection?
    var crossfaderOverride: Double?

    var isActive: Bool {
        !sceneMacroOverrides.isEmpty || abSelectionOverride != nil || crossfaderOverride != nil
    }

    func macroOverride(sceneID: UUID, macroID: UUID) -> Double? {
        sceneMacroOverrides[sceneID]?[macroID]
    }

    func macroOverrides(sceneID: UUID) -> [UUID: Double] {
        sceneMacroOverrides[sceneID] ?? [:]
    }

    func hasMacroOverrides(sceneID: UUID) -> Bool {
        !(sceneMacroOverrides[sceneID]?.isEmpty ?? true)
    }

    mutating func setMacroOverride(sceneID: UUID, macroID: UUID, value: Double) {
        sceneMacroOverrides[sceneID, default: [:]][macroID] = value
    }

    mutating func clearMacroOverrides(sceneID: UUID) {
        sceneMacroOverrides.removeValue(forKey: sceneID)
    }

    mutating func clearAll() {
        sceneMacroOverrides = [:]
        abSelectionOverride = nil
        crossfaderOverride = nil
    }

    func normalized(for masterBus: MasterBusState) -> MasterBusPerformanceOverlayState {
        var normalizedOverrides: [UUID: [UUID: Double]] = [:]
        for (sceneID, valuesByMacroID) in sceneMacroOverrides {
            guard let scene = masterBus.scene(id: sceneID) else { continue }
            let validMacroIDs = Set(scene.macroBindings.map(\.id))
            let filtered = valuesByMacroID.filter { validMacroIDs.contains($0.key) }
            if !filtered.isEmpty {
                normalizedOverrides[sceneID] = filtered
            }
        }

        let normalizedSelection: MasterBusABSelection?
        if let selection = abSelectionOverride?.normalized(),
           masterBus.scenes.contains(where: { $0.id == selection.sceneAID }),
           masterBus.scenes.contains(where: { $0.id == selection.sceneBID }),
           selection.sceneAID != selection.sceneBID
        {
            normalizedSelection = selection
        } else {
            normalizedSelection = nil
        }

        return MasterBusPerformanceOverlayState(
            sceneMacroOverrides: normalizedOverrides,
            abSelectionOverride: normalizedSelection,
            crossfaderOverride: crossfaderOverride?.clamped(to: 0...1)
        )
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

typealias MixerBusInsert = MasterBusInsert
typealias SendBusInsert = MasterBusInsert

struct BusMixSettings: Codable, Equatable, Hashable, Sendable {
    var level: Double
    var pan: Double
    var isMuted: Bool
    var isSoloed: Bool

    static let `default` = BusMixSettings(level: 1, pan: 0, isMuted: false, isSoloed: false)

    var clampedLevel: Double {
        min(max(level, 0), 1)
    }

    var clampedPan: Double {
        min(max(pan, -1), 1)
    }

    func normalized() -> BusMixSettings {
        BusMixSettings(level: clampedLevel, pan: clampedPan, isMuted: isMuted, isSoloed: isSoloed)
    }
}

struct MixerBus: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var color: String?
    var mix: BusMixSettings
    var inserts: [MixerBusInsert]

    init(
        id: UUID = UUID(),
        name: String,
        color: String? = nil,
        mix: BusMixSettings = .default,
        inserts: [MixerBusInsert] = []
    ) {
        self.id = id
        self.name = Self.normalizedName(name, fallback: "Bus")
        self.color = Self.normalizedColor(color)
        self.mix = mix.normalized()
        self.inserts = Self.normalizedInserts(inserts)
    }

    func normalized(fallbackName: String) -> MixerBus {
        MixerBus(
            id: id,
            name: Self.normalizedName(name, fallback: fallbackName),
            color: Self.normalizedColor(color),
            mix: mix.normalized(),
            inserts: Self.normalizedInserts(inserts)
        )
    }

    static func normalizedName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (fallbackName.isEmpty ? "Bus" : fallbackName) : trimmed
    }

    static func normalizedColor(_ color: String?) -> String? {
        let trimmed = color?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func normalizedCollection(_ buses: [MixerBus]) -> [MixerBus] {
        var seenIDs = Set<UUID>()
        return buses.enumerated().map { index, bus in
            var normalized = bus.normalized(fallbackName: "Bus \(index + 1)")
            if seenIDs.contains(normalized.id) {
                normalized.id = UUID()
            }
            seenIDs.insert(normalized.id)
            return normalized
        }
    }

    private static func normalizedInserts(_ inserts: [MixerBusInsert]) -> [MixerBusInsert] {
        var seenIDs = Set<UUID>()
        return inserts.map { insert in
            var normalized = insert.normalized()
            if seenIDs.contains(normalized.id) {
                normalized.id = UUID()
            }
            seenIDs.insert(normalized.id)
            return normalized
        }
    }
}

struct MasterBusInsert: Codable, Equatable, Hashable, Identifiable, Sendable {
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

enum MasterBusInsertKind: Codable, Equatable, Hashable, Sendable {
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

struct MasterFilterSettings: Codable, Equatable, Hashable, Sendable {
    enum Mode: String, Codable, CaseIterable, Hashable, Sendable {
        case lowPass
        case highPass
        case bandPass
        case notch
        case peak

        var displayName: String {
            switch self {
            case .lowPass: return "Low Pass"
            case .highPass: return "High Pass"
            case .bandPass: return "Band Pass"
            case .notch: return "Notch"
            case .peak: return "Peak"
            }
        }
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

struct MasterBitcrusherSettings: Codable, Equatable, Hashable, Sendable {
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
