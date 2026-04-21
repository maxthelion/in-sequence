import SwiftUI

struct TrackSourceEditorView: View {
    @Binding var document: SeqAIDocument
    let accent: Color

    private var track: StepSequenceTrack { document.project.selectedTrack }
    private var bank: TrackPatternBank { document.project.patternBank(for: track.id) }
    private var selectedPatternIndex: Int { document.project.selectedPatternIndex(for: track.id) }
    private var selectedPattern: TrackPatternSlot { document.project.selectedPattern(for: track.id) }
    private var occupiedPatternSlots: Set<Int> {
        Set(bank.slots.compactMap { slot in
            guard let clip = document.project.clipEntry(id: slot.sourceRef.clipID),
                  !clipIsEmpty(clip.content)
            else {
                return nil
            }
            return slot.slotIndex
        })
    }
    private var attachedGenerator: GeneratorPoolEntry? {
        document.project.generatorEntry(id: bank.attachedGeneratorID)
    }
    private var selectedSourceMode: TrackSourceMode { selectedPattern.sourceRef.mode }
    private var compatibleGenerators: [GeneratorPoolEntry] { document.project.compatibleGenerators(for: track) }
    private var generatedSourceInputClips: [ClipPoolEntry] { document.project.generatedSourceInputClips() }
    private var harmonicSidechainClips: [ClipPoolEntry] { document.project.harmonicSidechainClips() }
    private var currentClip: ClipPoolEntry? { document.project.clipEntry(id: selectedPattern.sourceRef.clipID) }
    private var previewClipContent: ClipContent {
        currentClip?.content
            ?? .stepSequence(stepPattern: Array(repeating: false, count: 16), pitches: track.pitches)
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
            eyebrow: "Pattern editor",
            accent: StudioTheme.violet
        ) {
            ClipContentPreview(content: previewClipContent) { updated in
                guard let clipID = document.project.ensureClipForCurrentPattern(trackID: track.id) else {
                    return
                }
                document.project.updateClipEntry(id: clipID) { entry in
                    entry.content = updated
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
}
