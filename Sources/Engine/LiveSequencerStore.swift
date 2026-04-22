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
    private(set) var project: Project

    init(project: Project) {
        self.project = project
    }

    var trackOrder: [UUID] {
        project.tracks.map(\.id)
    }

    var clipsByID: [UUID: EditableClipState] {
        Dictionary(uniqueKeysWithValues: project.clipPool.map { ($0.id, EditableClipState(entry: $0)) })
    }

    var patternBanksByTrackID: [UUID: TrackPatternBank] {
        Dictionary(uniqueKeysWithValues: project.tracks.map { ($0.id, project.patternBank(for: $0.id)) })
    }

    var phrasesByID: [UUID: PhraseModel] {
        Dictionary(uniqueKeysWithValues: project.phrases.map { ($0.id, $0) })
    }

    var generatorsByID: [UUID: GeneratorPoolEntry] {
        Dictionary(uniqueKeysWithValues: project.generatorPool.map { ($0.id, $0) })
    }

    var macroBindingsByTrackID: [UUID: [TrackMacroBinding]] {
        Dictionary(uniqueKeysWithValues: project.tracks.map { ($0.id, $0.macros) })
    }

    func replaceProject(_ project: Project) {
        self.project = project
    }

    func projectToProject(base: Project) -> Project {
        _ = base
        return project
    }

    func selectTrack(id: UUID) {
        project.selectTrack(id: id)
    }

    func selectPhrase(id: UUID) {
        project.selectPhrase(id: id)
    }

    func setSelectedPatternIndex(_ index: Int, for trackID: UUID) {
        project.setSelectedPatternIndex(index, for: trackID)
    }

    @discardableResult
    func ensureClipForCurrentPattern(trackID: UUID) -> UUID? {
        project.ensureClipForCurrentPattern(trackID: trackID)
    }

    func updateClipContent(id: UUID, content: ClipContent) {
        project.updateClipEntry(id: id) { entry in
            entry.content = content
            entry.macroLanes = entry.macroLanes.mapValues { lane in
                lane.synced(stepCount: content.stepCount)
            }
        }
    }

    func updateClipMacroLanes(id: UUID, lanes: [UUID: MacroLane]) {
        let stepCount = project.clipEntry(id: id)?.content.stepCount ?? 0
        project.updateClipEntry(id: id) { entry in
            entry.macroLanes = lanes.mapValues { $0.synced(stepCount: stepCount) }
        }
    }

    func updateGeneratorEntry(id: UUID, update: (inout GeneratorPoolEntry) -> Void) {
        project.updateGeneratorEntry(id: id, update)
    }

    @discardableResult
    func attachNewGenerator(to trackID: UUID) -> GeneratorPoolEntry? {
        project.attachNewGenerator(to: trackID)
    }

    func removeAttachedGenerator(from trackID: UUID) {
        project.removeAttachedGenerator(from: trackID)
    }

    func setSlotBypassed(_ bypassed: Bool, trackID: UUID, slotIndex: Int) {
        project.setSlotBypassed(bypassed, trackID: trackID, slotIndex: slotIndex)
    }

    func setPhraseCell(_ cell: PhraseCell, layerID: String, trackIDs: [UUID], phraseID: UUID? = nil) {
        project.setPhraseCell(cell, layerID: layerID, trackIDs: trackIDs, phraseID: phraseID)
    }

    func setPhraseCellMode(
        _ mode: PhraseCellEditMode,
        layer: PhraseLayerDefinition,
        trackIDs: [UUID],
        phraseID: UUID? = nil
    ) {
        project.setPhraseCellMode(mode, layer: layer, trackIDs: trackIDs, phraseID: phraseID)
    }

    func setMacroLayerDefault(value: Double, bindingID: UUID, trackID: UUID, phraseID: UUID? = nil) {
        project.setMacroLayerDefault(
            value: value,
            bindingID: bindingID,
            trackID: trackID,
            phraseID: phraseID ?? project.selectedPhraseID
        )
    }

    func insertPhrase(below phraseID: UUID) {
        project.insertPhrase(below: phraseID)
    }

    func duplicatePhrase(id phraseID: UUID) {
        project.duplicatePhrase(id: phraseID)
    }

    func removePhrase(id phraseID: UUID) {
        project.removePhrase(id: phraseID)
    }
}
