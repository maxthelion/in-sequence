import SwiftUI

struct TrackSourceEditorView: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    let accent: Color

    private var project: Project { session.projectView }
    private var track: StepSequenceTrack { project.selectedTrack }
    private var bank: TrackPatternBank { project.patternBank(for: track.id) }
    private var selectedPatternIndex: Int { project.selectedPatternIndex(for: track.id) }
    private var selectedPattern: TrackPatternSlot { project.selectedPattern(for: track.id) }
    private var occupiedPatternSlots: Set<Int> {
        Set(bank.slots.compactMap { slot in
            guard let clip = project.clipEntry(id: slot.sourceRef.clipID),
                  !clipIsEmpty(clip.content)
            else {
                return nil
            }
            return slot.slotIndex
        })
    }
    private var attachedGenerator: GeneratorPoolEntry? {
        project.generatorEntry(id: bank.attachedGeneratorID)
    }
    private var selectedSourceMode: TrackSourceMode { selectedPattern.sourceRef.mode }
    private var compatibleGenerators: [GeneratorPoolEntry] { project.compatibleGenerators(for: track) }
    private var generatedSourceInputClips: [ClipPoolEntry] { project.generatedSourceInputClips() }
    private var harmonicSidechainClips: [ClipPoolEntry] { project.harmonicSidechainClips() }
    private var currentClip: ClipPoolEntry? { project.clipEntry(id: selectedPattern.sourceRef.clipID) }
    private var previewClipContent: ClipContent {
        currentClip?.content
            ?? .stepSequence(stepPattern: Array(repeating: false, count: 16), pitches: track.pitches)
    }

    /// Phrase-layer fallback values for each macro binding on this track.
    ///
    /// Reads `layer.defaults[trackID]` for the binding's layer; falls back to the
    /// descriptor default when no layer default has been set.
    private var macroFallbackValues: [UUID: Double] {
        var result: [UUID: Double] = [:]
        let trackID = track.id
        for binding in track.macros {
            let layerID = "macro-\(trackID.uuidString)-\(binding.id.uuidString)"
            if let layer = project.layers.first(where: { $0.id == layerID }),
               case let .scalar(v) = layer.defaults[trackID] {
                result[binding.id] = v
            } else {
                result[binding.id] = binding.descriptor.defaultValue
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Source", accent: accent) {
                VStack(alignment: .leading, spacing: 14) {
                    TrackPatternSlotPalette(
                        selectedSlot: selectedPatternIndexBinding,
                        occupiedSlots: occupiedPatternSlots,
                        bypassState: bypassState,
                        onBypassToggle: { slotIndex in
                            let currentlyBypassed = (bank.slot(at: slotIndex).sourceRef.mode == .clip)
                            session.setSlotBypassed(!currentlyBypassed, trackID: track.id, slotIndex: slotIndex)
                        }
                    )

                    GeneratorAttachmentControl(
                        attachedGenerator: attachedGenerator,
                        accent: accent,
                        onAdd: {
                            _ = session.attachNewGenerator(to: track.id)
                        },
                        onRemove: {
                            session.removeAttachedGenerator(from: track.id)
                        }
                    )
                }
            }

            if selectedSourceMode == .generator, let attached = attachedGenerator {
                generatorEditorPanel(for: attached)
            }
            if selectedSourceMode == .clip {
                clipPanel
            }
        }
    }

    private var bypassState: TrackPatternSlotPalette.BypassState {
        guard bank.attachedGeneratorID != nil else {
            return .notApplicable
        }
        var bypassed: Set<Int> = []
        for (index, slot) in bank.slots.enumerated() where slot.sourceRef.mode == .clip {
            bypassed.insert(index)
        }
        return .applicable(bypassed: bypassed)
    }

    @ViewBuilder
    private func generatorEditorPanel(for generator: GeneratorPoolEntry) -> some View {
        GeneratorParamsEditorView(
            generator: generator,
            inputClipChoices: generatedSourceInputClips,
            harmonicSidechainClipChoices: harmonicSidechainClips,
            accent: accent
        ) { updated in
            session.updateGeneratorEntry(id: generator.id) { entry in
                entry.params = updated
            }
        }
    }

    @ViewBuilder
    private var clipPanel: some View {
        StudioPanel(
            title: "Clip",
            eyebrow: "Pattern editor",
            accent: StudioTheme.violet
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ClipContentPreview(content: previewClipContent) { updated in
                    guard let clipID = session.ensureClipForCurrentPattern(trackID: track.id) else {
                        return
                    }
                    session.updateClipContent(id: clipID, content: updated)
                }

                if !track.macros.isEmpty, let clip = currentClip {
                    ClipMacroLaneEditor(
                        clipID: clip.id,
                        macros: track.macros,
                        macroLanes: clip.macroLanes.mapValues { lane in
                            lane.synced(stepCount: clip.content.stepCount)
                        },
                        phraseLayerValues: macroFallbackValues
                    ) { updatedLanes in
                        session.updateClipMacroLanes(id: clip.id, lanes: updatedLanes)
                    }
                }
            }
        }
    }

    private var selectedPatternIndexBinding: Binding<Int> {
        Binding(
            get: { project.selectedPatternIndex(for: track.id) },
            set: { session.setSelectedPatternIndex($0, for: track.id) }
        )
    }
}
