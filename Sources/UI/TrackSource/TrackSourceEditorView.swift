import SwiftUI

struct TrackSourceEditorView: View {
    @Binding var document: SeqAIDocument
    let accent: Color

    private var track: StepSequenceTrack { document.project.selectedTrack }
    private var bank: TrackPatternBank { document.project.patternBank(for: track.id) }
    private var selectedPatternIndex: Int { document.project.selectedPatternIndex(for: track.id) }
    private var selectedPattern: TrackPatternSlot { document.project.selectedPattern(for: track.id) }
    private var occupiedPatternSlots: Set<Int> {
        Set(document.project.phrases.map { $0.patternIndex(for: track.id, layers: document.project.layers) })
    }
    private var attachedGenerator: GeneratorPoolEntry? {
        document.project.generatorEntry(id: bank.attachedGeneratorID)
    }
    private var selectedSourceMode: TrackSourceMode { selectedPattern.sourceRef.mode }
    private var compatibleGenerators: [GeneratorPoolEntry] { document.project.compatibleGenerators(for: track) }
    private var compatibleClips: [ClipPoolEntry] { document.project.compatibleClips(for: track) }
    private var generatedSourceInputClips: [ClipPoolEntry] { document.project.generatedSourceInputClips() }
    private var harmonicSidechainClips: [ClipPoolEntry] { document.project.harmonicSidechainClips() }
    private var currentClip: ClipPoolEntry? { document.project.clipEntry(id: selectedPattern.sourceRef.clipID) }

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
                            document.project.setSlotBypassed(!currentlyBypassed, trackID: track.id, slotIndex: slotIndex)
                        }
                    )

                    GeneratorAttachmentControl(
                        attachedGenerator: attachedGenerator,
                        accent: accent,
                        onAdd: {
                            _ = document.project.attachNewGenerator(to: track.id)
                        },
                        onRemove: {
                            document.project.removeAttachedGenerator(from: track.id)
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
            document.project.updateGeneratorEntry(id: generator.id) { entry in
                entry.params = updated
            }
        }
    }

    @ViewBuilder
    private var clipPanel: some View {
        StudioPanel(
            title: "Clip",
            eyebrow: currentClip == nil ? "No clip selected" : "Direct clip source",
            accent: StudioTheme.violet
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if compatibleClips.isEmpty {
                    StudioPlaceholderTile(
                        title: "No Compatible Clips",
                        detail: "Create or import a compatible clip for this track type.",
                        accent: StudioTheme.violet
                    )
                } else {
                    Picker("Clip", selection: clipIDBinding) {
                        Text("Choose Clip").tag(Optional<UUID>.none)
                        ForEach(compatibleClips) { entry in
                            Text(entry.name).tag(Optional(entry.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if let clip = currentClip {
                        ClipContentPreview(content: clip.content) { updated in
                            document.project.updateClipEntry(id: clip.id) { entry in
                                entry.content = updated
                            }
                        }
                    } else {
                        StudioPlaceholderTile(
                            title: "No Clip For This Slot",
                            detail: "Pick a clip from the pool for this pattern slot.",
                            accent: StudioTheme.violet
                        )
                    }
                }
            }
        }
    }

    private var selectedPatternIndexBinding: Binding<Int> {
        Binding(
            get: { document.project.selectedPatternIndex(for: track.id) },
            set: { document.project.setSelectedPatternIndex($0, for: track.id) }
        )
    }

    private var clipIDBinding: Binding<UUID?> {
        Binding(
            get: { selectedPattern.sourceRef.clipID },
            set: { newValue in
                guard let newValue else { return }
                document.project.setPatternClipID(newValue, for: track.id, slotIndex: selectedPatternIndex)
            }
        )
    }
}
