import SwiftUI

struct TrackSourceEditorView: View {
    @Binding var document: SeqAIDocument
    let accent: Color

    private var track: StepSequenceTrack { document.project.selectedTrack }
    private var phrase: PhraseModel { document.project.selectedPhrase }
    private var selectedPatternIndex: Int { document.project.selectedPatternIndex(for: track.id) }
    private var selectedPattern: TrackPatternSlot { document.project.selectedPattern(for: track.id) }
    private var occupiedPatternSlots: Set<Int> {
        Set(document.project.phrases.map { $0.patternIndex(for: track.id, layers: document.project.layers) })
    }
    private var selectedSourceMode: TrackSourceMode { selectedPattern.sourceRef.mode }
    private var compatibleGenerators: [GeneratorPoolEntry] { document.project.compatibleGenerators(for: track) }
    private var compatibleClips: [ClipPoolEntry] { document.project.compatibleClips(for: track) }
    private var currentGenerator: GeneratorPoolEntry? { document.project.generatorEntry(id: selectedPattern.sourceRef.generatorID) }
    private var currentClip: ClipPoolEntry? { document.project.clipEntry(id: selectedPattern.sourceRef.clipID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Source", accent: accent) {
                VStack(alignment: .leading, spacing: 14) {
                    TrackPatternSlotPalette(
                        selectedSlot: selectedPatternIndexBinding,
                        occupiedSlots: occupiedPatternSlots
                    )

                    TrackSourceModePalette(trackType: track.trackType, selectedSource: selectedSourceModeBinding)
                }
            }

            switch selectedSourceMode {
            case .generator:
                generatorPanels
            case .clip:
                clipPanels
            }
        }
    }

    private var generatorPanels: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Generator", eyebrow: currentGenerator?.kind.label ?? "No generator selected", accent: accent) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Generator", selection: generatorIDBinding) {
                        ForEach(compatibleGenerators) { generator in
                            Text(generator.name).tag(Optional(generator.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if let generator = currentGenerator {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(generator.name)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.text)

                            Text(generatorSummary(generator))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                        }
                    }
                }
            }

            if let generator = currentGenerator {
                GeneratorParamsEditorView(
                    generator: generator,
                    clipChoices: compatibleClips,
                    accent: accent
                ) { updated in
                    document.project.updateGeneratorEntry(id: generator.id) { entry in
                        entry.params = updated
                    }
                }
            } else {
                StudioPanel(title: "Generator Params", eyebrow: "No source selected", accent: accent) {
                    StudioPlaceholderTile(
                        title: "Choose A Generator",
                        detail: "A generator-backed pattern slot should show its step and pitch parameters here."
                    )
                }
            }
        }
    }

    private var clipPanels: some View {
        VStack(alignment: .leading, spacing: 18) {
            if compatibleClips.isEmpty {
                StudioPanel(title: "Clip", eyebrow: "No clip selected", accent: StudioTheme.violet) {
                    StudioPlaceholderTile(
                        title: "No Clip For This Track Type",
                        detail: "Create or attach a compatible clip to preview its notes here.",
                        accent: StudioTheme.violet
                    )
                }
            } else if let clip = currentClip {
                StudioPanel(title: "Clip Notes", eyebrow: clipPreviewEyebrow(clip), accent: StudioTheme.violet) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Clip", selection: clipIDBinding) {
                            ForEach(compatibleClips) { clip in
                                Text(clip.name).tag(Optional(clip.id))
                            }
                        }
                        .pickerStyle(.menu)

                        ClipContentPreview(content: clip.content) { updated in
                            document.project.updateClipEntry(id: clip.id) { entry in
                                entry.content = updated
                            }
                        }
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

    private var selectedSourceModeBinding: Binding<TrackSourceMode> {
        Binding(
            get: { selectedSourceMode },
            set: { newValue in
                switch newValue {
                case .generator:
                    if let generator = compatibleGenerators.first {
                        document.project.setPatternGeneratorID(generator.id, for: track.id, slotIndex: selectedPatternIndex)
                    } else {
                        document.project.setPatternSourceMode(.generator, for: track.id, slotIndex: selectedPatternIndex)
                    }
                case .clip:
                    if let clip = document.project.ensureCompatibleClip(for: track) {
                        document.project.setPatternClipID(clip.id, for: track.id, slotIndex: selectedPatternIndex)
                    } else {
                        document.project.setPatternSourceMode(.clip, for: track.id, slotIndex: selectedPatternIndex)
                    }
                }
            }
        )
    }

    private var generatorIDBinding: Binding<UUID?> {
        Binding(
            get: { selectedPattern.sourceRef.generatorID },
            set: { newValue in
                guard let newValue else { return }
                document.project.setPatternGeneratorID(newValue, for: track.id, slotIndex: selectedPatternIndex)
            }
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

    private func generatorSummary(_ generator: GeneratorPoolEntry) -> String {
        switch generator.params {
        case let .mono(step, pitch, shape):
            return "\(stepDisplayLabel(step)) steps • \(pitchDisplayLabel(pitch)) pitches • vel \(shape.velocity) • gate \(shape.gateLength)"
        case let .poly(step, pitches, shape):
            return "\(stepDisplayLabel(step)) steps • \(pitches.count) pitch lanes • vel \(shape.velocity) • gate \(shape.gateLength)"
        case let .drum(steps, shape):
            return "\(steps.count) drum lanes • vel \(shape.velocity) • gate \(shape.gateLength)"
        case .template:
            return "Template-driven source"
        case let .slice(step, sliceIndexes):
            return "\(stepDisplayLabel(step)) steps • \(sliceIndexes.count) slice indexes"
        }
    }

private func clipPreviewEyebrow(_ clip: ClipPoolEntry) -> String {
        switch clip.content {
        case .stepSequence:
            return "Step Sequencer"
        case .pianoRoll:
            return "Piano Roll"
        case .sliceTriggers:
            return "Slice Trigger Grid"
        }
    }
}
