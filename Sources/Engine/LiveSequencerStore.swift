import Foundation

struct EditableClipState: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var trackType: TrackType
    var content: ClipContent
    var macroLanes: [UUID: MacroLane]

    init(entry: ClipPoolEntry) {
        id = entry.id
        name = entry.name
        trackType = entry.trackType
        content = entry.content
        macroLanes = entry.macroLanes
    }

    var entry: ClipPoolEntry {
        ClipPoolEntry(id: id, name: name, trackType: trackType, content: content, macroLanes: macroLanes)
    }
}

@MainActor
final class LiveSequencerStore {
    private(set) var version: Int = 1
    private(set) var trackOrder: [UUID] = []
    private(set) var tracksByID: [UUID: StepSequenceTrack] = [:]
    private(set) var trackGroups: [TrackGroup] = []
    private(set) var generatorOrder: [UUID] = []
    private(set) var generatorsByID: [UUID: GeneratorPoolEntry] = [:]
    private(set) var clipOrder: [UUID] = []
    private(set) var clipsByID: [UUID: EditableClipState] = [:]
    private(set) var layers: [PhraseLayerDefinition] = []
    private(set) var routes: [Route] = []
    private(set) var patternBanksByTrackID: [UUID: TrackPatternBank] = [:]
    private(set) var selectedTrackID: UUID = StepSequenceTrack.default.id
    private(set) var phraseOrder: [UUID] = []
    private(set) var phrasesByID: [UUID: PhraseModel] = [:]
    private(set) var selectedPhraseID: UUID = PhraseModel.default(tracks: [StepSequenceTrack.default]).id

    init(project: Project) {
        load(from: project)
    }

    var project: Project {
        projectToProject(base: .empty)
    }

    var tracks: [StepSequenceTrack] {
        trackOrder.compactMap { tracksByID[$0] }
    }

    var generatorPool: [GeneratorPoolEntry] {
        generatorOrder.compactMap { generatorsByID[$0] }
    }

    var clipPool: [ClipPoolEntry] {
        clipOrder.compactMap { clipsByID[$0]?.entry }
    }

    var phrases: [PhraseModel] {
        phraseOrder.compactMap { phrasesByID[$0] }
    }

    var macroBindingsByTrackID: [UUID: [TrackMacroBinding]] {
        Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0.macros) })
    }

    func replaceProject(_ project: Project) {
        load(from: project)
    }

    func projectToProject(base: Project) -> Project {
        let tracks = self.tracks
        let clipPool = self.clipPool
        let phrases = self.phrases
        let selectedTrackID = tracks.contains(where: { $0.id == self.selectedTrackID })
            ? self.selectedTrackID
            : tracks.first?.id ?? StepSequenceTrack.default.id
        let selectedPhraseID = phrases.contains(where: { $0.id == self.selectedPhraseID })
            ? self.selectedPhraseID
            : phrases.first?.id ?? PhraseModel.default(tracks: tracks.isEmpty ? [StepSequenceTrack.default] : tracks).id

        let patternBanks = tracks.map { track in
            patternBanksByTrackID[track.id]
                ?? TrackPatternBank.default(
                    for: track,
                    initialClipID: clipPool.first(where: { $0.trackType == track.trackType })?.id
                )
        }

        return Project(
            version: version == 0 ? base.version : version,
            tracks: tracks,
            trackGroups: trackGroups,
            generatorPool: generatorPool,
            clipPool: clipPool,
            layers: layers,
            routes: routes,
            patternBanks: patternBanks,
            selectedTrackID: selectedTrackID,
            phrases: phrases,
            selectedPhraseID: selectedPhraseID
        )
    }

    func compatibleGenerators(for track: StepSequenceTrack) -> [GeneratorPoolEntry] {
        generatorPool.filter { $0.trackType == track.trackType }
    }

    func compatibleClips(for track: StepSequenceTrack) -> [ClipPoolEntry] {
        clipPool.filter { $0.trackType == track.trackType }
    }

    func generatedSourceInputClips() -> [ClipPoolEntry] {
        clipPool
    }

    func harmonicSidechainClips() -> [ClipPoolEntry] {
        clipPool.filter(\.hasPitchMaterial)
    }

    func generatorEntry(id: UUID?) -> GeneratorPoolEntry? {
        guard let id else { return nil }
        return generatorsByID[id]
    }

    func clipEntry(id: UUID?) -> ClipPoolEntry? {
        guard let id else { return nil }
        return clipsByID[id]?.entry
    }

    func patternBank(for trackID: UUID) -> TrackPatternBank {
        if let existing = patternBanksByTrackID[trackID] {
            return existing
        }
        let track = tracksByID[trackID] ?? .default
        let fallbackClipID = clipPool.first(where: { $0.trackType == track.trackType })?.id
        return TrackPatternBank.default(for: track, initialClipID: fallbackClipID)
    }

    func layer(id: String) -> PhraseLayerDefinition? {
        layers.first(where: { $0.id == id })
    }

    func selectedPatternIndex(for trackID: UUID) -> Int {
        selectedPhrase.patternIndex(for: trackID, layers: layers)
    }

    func selectTrack(id: UUID) {
        guard tracksByID[id] != nil else {
            return
        }
        selectedTrackID = id
    }

    func selectPhrase(id: UUID) {
        guard phrasesByID[id] != nil else {
            return
        }
        selectedPhraseID = id
    }

    func setSelectedPatternIndex(_ index: Int, for trackID: UUID) {
        guard var phrase = phrasesByID[selectedPhraseID] else {
            return
        }
        phrase.setPatternIndex(index, for: trackID, layers: layers)
        phrasesByID[phrase.id] = phrase.synced(with: tracks, layers: layers)
        selectedPhraseID = phrase.id
    }

    @discardableResult
    func ensureClipForCurrentPattern(trackID: UUID) -> UUID? {
        let slotIndex = selectedPatternIndex(for: trackID)
        guard var bank = patternBanksByTrackID[trackID] else {
            NSLog("[LiveSequencerStore] ensureClipForCurrentPattern missing pattern bank trackID=\(trackID)")
            return nil
        }

        let slot = bank.slot(at: slotIndex)
        if let existing = slot.sourceRef.clipID {
            return existing
        }

        guard let track = tracksByID[trackID] else {
            return nil
        }

        let newClip = EditableClipState(
            entry: ClipPoolEntry(
                id: UUID(),
                name: "\(track.name) pattern \(slotIndex + 1)",
                trackType: track.trackType,
                content: .stepSequence(
                    stepPattern: Array(repeating: false, count: 16),
                    pitches: track.pitches
                )
            )
        )
        clipOrder.append(newClip.id)
        clipsByID[newClip.id] = newClip

        let merged = SourceRef(
            mode: .clip,
            generatorID: slot.sourceRef.generatorID,
            clipID: newClip.id
        )
        bank.setSlot(
            TrackPatternSlot(slotIndex: slot.slotIndex, name: slot.name, sourceRef: merged),
            at: slotIndex
        )
        patternBanksByTrackID[trackID] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
        return newClip.id
    }

    func updateClipContent(id: UUID, content: ClipContent) {
        guard var clip = clipsByID[id] else {
            return
        }
        clip.content = content
        clip.macroLanes = clip.macroLanes.mapValues { $0.synced(stepCount: content.stepCount) }
        clipsByID[id] = clip
    }

    func updateClipMacroLanes(id: UUID, lanes: [UUID: MacroLane]) {
        guard var clip = clipsByID[id] else {
            return
        }
        let stepCount = clip.content.stepCount
        clip.macroLanes = lanes.mapValues { $0.synced(stepCount: stepCount) }
        clipsByID[id] = clip
    }

    func updateGeneratorEntry(id: UUID, update: (inout GeneratorPoolEntry) -> Void) {
        guard var entry = generatorsByID[id] else {
            return
        }
        update(&entry)
        generatorsByID[id] = entry
    }

    @discardableResult
    func attachNewGenerator(to trackID: UUID) -> GeneratorPoolEntry? {
        guard let track = tracksByID[trackID],
              var bank = patternBanksByTrackID[trackID]
        else {
            return nil
        }

        guard let templateKind = GeneratorKind.allCases.first(where: { $0.compatibleWith.contains(track.trackType) }) else {
            return nil
        }

        let nextIndex = generatorPool.filter { $0.trackType == track.trackType }.count + 1
        let newEntry = GeneratorPoolEntry(
            id: UUID(),
            name: "\(templateKind.label) \(nextIndex)",
            trackType: track.trackType,
            kind: templateKind,
            params: templateKind.defaultParams
        )
        generatorOrder.append(newEntry.id)
        generatorsByID[newEntry.id] = newEntry

        bank.attachedGeneratorID = newEntry.id
        for index in 0..<bank.slots.count {
            let existing = bank.slots[index]
            let newRef = SourceRef(mode: .generator, generatorID: newEntry.id, clipID: existing.sourceRef.clipID)
            bank.slots[index] = TrackPatternSlot(slotIndex: existing.slotIndex, name: existing.name, sourceRef: newRef)
        }
        patternBanksByTrackID[trackID] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
        return newEntry
    }

    func removeAttachedGenerator(from trackID: UUID) {
        guard let track = tracksByID[trackID],
              var bank = patternBanksByTrackID[trackID],
              bank.attachedGeneratorID != nil
        else {
            return
        }

        bank.attachedGeneratorID = nil
        for index in 0..<bank.slots.count {
            let existing = bank.slots[index]
            let newRef = SourceRef(
                mode: .clip,
                generatorID: existing.sourceRef.generatorID,
                clipID: existing.sourceRef.clipID
            )
            bank.slots[index] = TrackPatternSlot(slotIndex: existing.slotIndex, name: existing.name, sourceRef: newRef)
        }
        patternBanksByTrackID[trackID] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
    }

    func setSlotBypassed(_ bypassed: Bool, trackID: UUID, slotIndex: Int) {
        guard let track = tracksByID[trackID],
              var bank = patternBanksByTrackID[trackID],
              bank.attachedGeneratorID != nil
        else {
            return
        }

        let clamped = min(max(slotIndex, 0), TrackPatternBank.slotCount - 1)
        let existing = bank.slot(at: clamped)
        let newMode: TrackSourceMode = bypassed ? .clip : .generator
        let newRef = SourceRef(
            mode: newMode,
            generatorID: existing.sourceRef.generatorID,
            clipID: existing.sourceRef.clipID
        )
        bank.setSlot(
            TrackPatternSlot(slotIndex: existing.slotIndex, name: existing.name, sourceRef: newRef),
            at: clamped
        )
        patternBanksByTrackID[trackID] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
    }

    func setPhraseCell(_ cell: PhraseCell, layerID: String, trackIDs: [UUID], phraseID: UUID? = nil) {
        let resolvedID = phraseID ?? selectedPhraseID
        guard var phrase = phrasesByID[resolvedID] else {
            return
        }
        for trackID in trackIDs {
            phrase.setCell(cell, for: layerID, trackID: trackID)
        }
        phrasesByID[resolvedID] = phrase.synced(with: tracks, layers: layers)
        selectedPhraseID = resolvedID
    }

    func setPhraseCellMode(
        _ mode: PhraseCellEditMode,
        layer: PhraseLayerDefinition,
        trackIDs: [UUID],
        phraseID: UUID? = nil
    ) {
        let resolvedID = phraseID ?? selectedPhraseID
        guard var phrase = phrasesByID[resolvedID] else {
            return
        }
        for trackID in trackIDs {
            phrase.setCellMode(mode, for: layer, trackID: trackID)
        }
        phrasesByID[resolvedID] = phrase.synced(with: tracks, layers: layers)
        selectedPhraseID = resolvedID
    }

    func setMacroLayerDefault(value: Double, bindingID: UUID, trackID: UUID, phraseID: UUID? = nil) {
        let layerID = "macro-\(trackID.uuidString)-\(bindingID.uuidString)"
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }) else {
            return
        }
        layers[layerIndex].defaults[trackID] = .scalar(value)
        if let phraseID, phrasesByID[phraseID] != nil {
            selectedPhraseID = phraseID
        }
    }

    func insertPhrase(below phraseID: UUID) {
        guard let index = phraseOrder.firstIndex(of: phraseID) else {
            appendPhrase()
            return
        }

        var nextPhrase = makeDefaultPhrase()
        nextPhrase.id = UUID()
        nextPhrase.name = defaultPhraseName(for: phraseOrder.count)
        let insertionIndex = min(index + 1, phraseOrder.count)
        phraseOrder.insert(nextPhrase.id, at: insertionIndex)
        phrasesByID[nextPhrase.id] = nextPhrase.synced(with: tracks, layers: layers)
        selectedPhraseID = nextPhrase.id
    }

    func duplicatePhrase(id phraseID: UUID) {
        guard let index = phraseOrder.firstIndex(of: phraseID),
              var duplicate = phrasesByID[phraseID]
        else {
            return
        }

        duplicate.id = UUID()
        duplicate.name = "\(phrasesByID[phraseID]?.name ?? "Phrase") Copy"
        let insertionIndex = min(index + 1, phraseOrder.count)
        phraseOrder.insert(duplicate.id, at: insertionIndex)
        phrasesByID[duplicate.id] = duplicate.synced(with: tracks, layers: layers)
        selectedPhraseID = duplicate.id
    }

    func removePhrase(id phraseID: UUID) {
        guard phraseOrder.count > 1,
              let index = phraseOrder.firstIndex(of: phraseID)
        else {
            return
        }

        phraseOrder.remove(at: index)
        phrasesByID.removeValue(forKey: phraseID)
        let nextIndex = min(index, phraseOrder.count - 1)
        selectedPhraseID = phraseOrder[nextIndex]
    }

    private var selectedPhrase: PhraseModel {
        if let phrase = phrasesByID[selectedPhraseID] {
            return phrase
        }
        if let phrase = phrases.first {
            return phrase
        }
        return makeDefaultPhrase()
    }

    private func appendPhrase() {
        var nextPhrase = makeDefaultPhrase()
        nextPhrase.id = UUID()
        nextPhrase.name = defaultPhraseName(for: phraseOrder.count)
        phraseOrder.append(nextPhrase.id)
        phrasesByID[nextPhrase.id] = nextPhrase.synced(with: tracks, layers: layers)
        selectedPhraseID = nextPhrase.id
    }

    private func makeDefaultPhrase() -> PhraseModel {
        PhraseModel.default(
            tracks: tracks.isEmpty ? [StepSequenceTrack.default] : tracks,
            layers: layers.isEmpty ? nil : layers,
            generatorPool: generatorPool,
            clipPool: clipPool
        )
    }

    private func defaultPhraseName(for index: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        if alphabet.indices.contains(index) {
            return "Phrase \(alphabet[index])"
        }
        return "Phrase \(index + 1)"
    }

    private func load(from project: Project) {
        version = project.version
        trackOrder = project.tracks.map(\.id)
        tracksByID = Dictionary(uniqueKeysWithValues: project.tracks.map { ($0.id, $0) })
        trackGroups = project.trackGroups

        generatorOrder = project.generatorPool.map(\.id)
        generatorsByID = Dictionary(uniqueKeysWithValues: project.generatorPool.map { ($0.id, $0) })

        clipOrder = project.clipPool.map(\.id)
        clipsByID = Dictionary(uniqueKeysWithValues: project.clipPool.map { ($0.id, EditableClipState(entry: $0)) })

        layers = project.layers
        routes = project.routes
        patternBanksByTrackID = Dictionary(uniqueKeysWithValues: project.patternBanks.map { ($0.trackID, $0) })
        selectedTrackID = project.selectedTrackID

        phraseOrder = project.phrases.map(\.id)
        phrasesByID = Dictionary(uniqueKeysWithValues: project.phrases.map { ($0.id, $0) })
        selectedPhraseID = project.selectedPhraseID
    }
}
