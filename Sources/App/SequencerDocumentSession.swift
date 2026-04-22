import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class SequencerDocumentSession {
    private let document: Binding<SeqAIDocument>
    @ObservationIgnored
    private let engineController: EngineController
    @ObservationIgnored
    private var flushWorkItem: DispatchWorkItem?
    @ObservationIgnored
    private var lastProjectedProject: Project?

    private(set) var revision: UInt64 = 0
    private(set) var projectView: Project
    let store: LiveSequencerStore

    init(document: Binding<SeqAIDocument>, engineController: EngineController) {
        self.document = document
        self.engineController = engineController
        self.projectView = document.wrappedValue.project
        self.store = LiveSequencerStore(project: document.wrappedValue.project)
        SeqAIDocumentProjectionRegistry.store(project: projectView, for: document.wrappedValue.runtimeID)
        SequencerDocumentSessionRegistry.register(runtimeID: document.wrappedValue.runtimeID) { [weak self] in
            self?.flushToDocument()
        }
        engineController.apply(documentModel: projectView)
        publishSnapshot()
    }

    deinit {
        let runtimeID = document.wrappedValue.runtimeID
        SeqAIDocumentProjectionRegistry.remove(runtimeID: runtimeID)
        Task { @MainActor in
            SequencerDocumentSessionRegistry.unregister(runtimeID: runtimeID)
        }
    }

    func publishSnapshot() {
        let snapshot = SequencerSnapshotCompiler.compile(project: store.project)
        engineController.apply(playbackSnapshot: snapshot)
    }

    func scheduleFlushToDocument() {
        flushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.flushToDocument()
            }
        }
        flushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    func flushToDocument() {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        document.wrappedValue.project = projectView
        lastProjectedProject = projectView
        SeqAIDocumentProjectionRegistry.store(project: projectView, for: document.wrappedValue.runtimeID)
    }

    func handleDocumentProjectChange(_ newProject: Project) {
        if let lastProjectedProject, lastProjectedProject == newProject {
            return
        }
        if projectView == newProject {
            return
        }
        store.replaceProject(newProject)
        projectView = newProject
        SeqAIDocumentProjectionRegistry.store(project: newProject, for: document.wrappedValue.runtimeID)
        revision &+= 1
        engineController.apply(documentModel: newProject)
        publishSnapshot()
    }

    func mutate(_ body: (LiveSequencerStore) -> Void) {
        body(store)
        projectView = store.projectToProject(base: projectView)
        SeqAIDocumentProjectionRegistry.store(project: projectView, for: document.wrappedValue.runtimeID)
        revision &+= 1
        publishSnapshot()
        scheduleFlushToDocument()
    }

    func selectTrack(id: UUID) {
        mutate { $0.selectTrack(id: id) }
    }

    func selectPhrase(id: UUID) {
        mutate { $0.selectPhrase(id: id) }
    }

    func setSelectedPatternIndex(_ index: Int, for trackID: UUID) {
        mutate { $0.setSelectedPatternIndex(index, for: trackID) }
    }

    @discardableResult
    func ensureClipForCurrentPattern(trackID: UUID) -> UUID? {
        var clipID: UUID?
        mutate {
            clipID = $0.ensureClipForCurrentPattern(trackID: trackID)
        }
        return clipID
    }

    func updateClipContent(id: UUID, content: ClipContent) {
        mutate { $0.updateClipContent(id: id, content: content) }
    }

    func updateClipMacroLanes(id: UUID, lanes: [UUID: MacroLane]) {
        mutate { $0.updateClipMacroLanes(id: id, lanes: lanes) }
    }

    func updateGeneratorEntry(id: UUID, update: @escaping (inout GeneratorPoolEntry) -> Void) {
        mutate { $0.updateGeneratorEntry(id: id, update: update) }
    }

    @discardableResult
    func attachNewGenerator(to trackID: UUID) -> GeneratorPoolEntry? {
        var generator: GeneratorPoolEntry?
        mutate {
            generator = $0.attachNewGenerator(to: trackID)
        }
        return generator
    }

    func removeAttachedGenerator(from trackID: UUID) {
        mutate { $0.removeAttachedGenerator(from: trackID) }
    }

    func setSlotBypassed(_ bypassed: Bool, trackID: UUID, slotIndex: Int) {
        mutate { $0.setSlotBypassed(bypassed, trackID: trackID, slotIndex: slotIndex) }
    }

    func setPhraseCell(_ cell: PhraseCell, layerID: String, trackIDs: [UUID], phraseID: UUID? = nil) {
        mutate { $0.setPhraseCell(cell, layerID: layerID, trackIDs: trackIDs, phraseID: phraseID) }
    }

    func setPhraseCellMode(
        _ mode: PhraseCellEditMode,
        layer: PhraseLayerDefinition,
        trackIDs: [UUID],
        phraseID: UUID? = nil
    ) {
        mutate { $0.setPhraseCellMode(mode, layer: layer, trackIDs: trackIDs, phraseID: phraseID) }
    }

    func setMacroLayerDefault(value: Double, bindingID: UUID, trackID: UUID, phraseID: UUID? = nil) {
        mutate { $0.setMacroLayerDefault(value: value, bindingID: bindingID, trackID: trackID, phraseID: phraseID) }
    }

    func insertPhrase(below phraseID: UUID) {
        mutate { $0.insertPhrase(below: phraseID) }
    }

    func duplicatePhrase(id phraseID: UUID) {
        mutate { $0.duplicatePhrase(id: phraseID) }
    }

    func removePhrase(id phraseID: UUID) {
        mutate { $0.removePhrase(id: phraseID) }
    }
}
