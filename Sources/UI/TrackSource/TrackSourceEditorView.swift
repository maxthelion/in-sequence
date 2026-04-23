import SwiftUI

private enum TrackSourceEditorTab: String, CaseIterable, Identifiable {
    case source
    case modifiers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source:
            return "Source"
        case .modifiers:
            return "Modifiers"
        }
    }
}

private enum GeneratorPickerPurpose: String, Identifiable {
    case source
    case modifier

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source:
            return "Select Source Generator"
        case .modifier:
            return "Select Modifier"
        }
    }
}

struct TrackSourceEditorView: View {
    @Binding var document: SeqAIDocument
    let accent: Color

    @State private var selectedTab: TrackSourceEditorTab = .source
    @State private var generatorPickerPurpose: GeneratorPickerPurpose?

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
    private var selectedSourceMode: TrackSourceMode { selectedPattern.sourceRef.mode }
    private var compatibleGenerators: [GeneratorPoolEntry] { document.project.compatibleGenerators(for: track) }
    private var generatedSourceInputClips: [ClipPoolEntry] { document.project.generatedSourceInputClips() }
    private var harmonicSidechainClips: [ClipPoolEntry] { document.project.harmonicSidechainClips() }
    private var currentClip: ClipPoolEntry? { document.project.clipEntry(id: selectedPattern.sourceRef.clipID) }
    private var selectedSourceGenerator: GeneratorPoolEntry? {
        document.project.generatorEntry(id: selectedPattern.sourceRef.generatorID)
    }
    private var selectedModifierGenerator: GeneratorPoolEntry? {
        document.project.generatorEntry(id: selectedPattern.sourceRef.modifierGeneratorID)
    }
    private var previewClipContent: ClipContent {
        currentClip?.content
            ?? .emptyNoteGrid(lengthSteps: 16)
    }
    private var defaultClipNote: ClipStepNote {
        ClipStepNote(
            pitch: track.pitches.first ?? 60,
            velocity: track.velocity,
            lengthSteps: track.gateLength
        ).normalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Pattern", accent: accent) {
                VStack(alignment: .leading, spacing: 14) {
                    TrackPatternSlotPalette(
                        selectedSlot: selectedPatternIndexBinding,
                        occupiedSlots: occupiedPatternSlots,
                        bypassState: .notApplicable,
                        onBypassToggle: { _ in }
                    )

                    Picker("Editor Section", selection: $selectedTab) {
                        ForEach(TrackSourceEditorTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Group {
                switch selectedTab {
                case .source:
                    sourceTab
                case .modifiers:
                    modifiersTab
                }
            }
        }
        .sheet(item: $generatorPickerPurpose) { purpose in
            GeneratorSelectionSheet(
                title: purpose.title,
                generators: compatibleGenerators,
                onSelect: { generator in
                    select(generator: generator, for: purpose)
                    generatorPickerPurpose = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationBackground(.clear)
        }
    }

    @ViewBuilder
    private var sourceTab: some View {
        switch selectedSourceMode {
        case .clip:
            clipPanel

            StudioPanel(
                title: "Clip Source",
                eyebrow: currentClip == nil
                    ? "This slot will create a blank clip the first time you edit it."
                    : "This slot is currently playing a clip.",
                accent: accent
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Use the clip editor above, or swap this slot to a generator source.")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)

                    if compatibleGenerators.isEmpty {
                        Text("No compatible generators are available for this track yet.")
                            .studioText(.body)
                            .foregroundStyle(StudioTheme.mutedText)
                    } else {
                        actionButton(title: "Switch To Generator Source", accent: accent) {
                            generatorPickerPurpose = .source
                        }
                    }
                }
            }

        case .generator:
            if let generator = selectedSourceGenerator {
                StudioPanel(title: "Generator Source", eyebrow: generator.name, accent: accent) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("This slot is using \(generator.kind.label.lowercased()) as its source.")
                            .studioText(.body)
                            .foregroundStyle(StudioTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            actionButton(title: "Choose Different Generator", accent: accent) {
                                generatorPickerPurpose = .source
                            }
                            actionButton(title: "Remove Generator Source", accent: StudioTheme.violet) {
                                removeGeneratorSource()
                            }
                        }
                    }
                }

                GeneratorParamsEditorView(
                    generator: generator,
                    inputClipChoices: generatedSourceInputClips,
                    harmonicSidechainClipChoices: harmonicSidechainClips,
                    sourceMode: .generator,
                    accent: accent,
                    layout: .sourceOnly
                ) { updated in
                    document.project.updateGeneratorEntry(id: generator.id) { entry in
                        entry.params = updated
                    }
                }
            } else {
                StudioPanel(title: "Generator Source", eyebrow: "No source generator selected.", accent: accent) {
                    actionButton(title: "Select Generator", accent: accent) {
                        generatorPickerPurpose = .source
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var modifiersTab: some View {
        if let generator = selectedModifierGenerator {
            StudioPanel(title: "Modifier", eyebrow: generator.name, accent: StudioTheme.violet) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(
                        selectedPattern.sourceRef.modifierBypassed
                            ? "This modifier is bypassed. Re-enable it to hear its pitch processing."
                            : "Pitch processing runs after the selected source for this slot."
                    )
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        actionButton(title: "Choose Different Modifier", accent: StudioTheme.violet) {
                            generatorPickerPurpose = .modifier
                        }
                        actionButton(
                            title: selectedPattern.sourceRef.modifierBypassed ? "Enable" : "Bypass",
                            accent: selectedPattern.sourceRef.modifierBypassed ? StudioTheme.success : StudioTheme.amber
                        ) {
                            document.project.setPatternModifierBypassed(
                                !selectedPattern.sourceRef.modifierBypassed,
                                for: track.id,
                                slotIndex: selectedPatternIndex
                            )
                        }
                        actionButton(title: "Remove Modifier", accent: StudioTheme.border) {
                            document.project.setPatternModifierGeneratorID(
                                nil,
                                for: track.id,
                                slotIndex: selectedPatternIndex
                            )
                        }
                    }
                }
            }

            GeneratorParamsEditorView(
                generator: generator,
                inputClipChoices: generatedSourceInputClips,
                harmonicSidechainClipChoices: harmonicSidechainClips,
                sourceMode: selectedSourceMode,
                accent: accent,
                layout: .modifierOnly
            ) { updated in
                document.project.updateGeneratorEntry(id: generator.id) { entry in
                    entry.params = updated
                }
            }
        } else {
            StudioPanel(title: "Modifiers", eyebrow: "Empty by default.", accent: StudioTheme.violet) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("This slot currently has no modifier. Add one to process the source after it has been resolved.")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)

                    if compatibleGenerators.isEmpty {
                        Text("No compatible generators are available for this track yet.")
                            .studioText(.body)
                            .foregroundStyle(StudioTheme.mutedText)
                    } else {
                        actionButton(title: "Add Modifier", accent: StudioTheme.violet) {
                            generatorPickerPurpose = .modifier
                        }
                    }
                }
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
            ClipContentPreview(content: previewClipContent, defaultNote: defaultClipNote) { updated in
                guard let clipID = document.project.ensureClipForCurrentPattern(trackID: track.id) else {
                    return
                }
                document.project.updateClipEntry(id: clipID) { entry in
                    entry.content = updated
                }
            }
        }
    }

    private func actionButton(title: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(accent.opacity(StudioOpacity.selectedFill), in: Capsule())
                .overlay(Capsule().stroke(accent.opacity(StudioOpacity.ghostStroke), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func select(generator: GeneratorPoolEntry, for purpose: GeneratorPickerPurpose) {
        switch purpose {
        case .source:
            let updated = SourceRef(
                mode: .generator,
                generatorID: generator.id,
                clipID: selectedPattern.sourceRef.clipID,
                modifierGeneratorID: selectedPattern.sourceRef.modifierGeneratorID,
                modifierBypassed: selectedPattern.sourceRef.modifierBypassed
            )
            document.project.setPatternSourceRef(updated, for: track.id, slotIndex: selectedPatternIndex)

        case .modifier:
            var clipID = selectedPattern.sourceRef.clipID
            if selectedSourceMode == .clip, clipID == nil {
                clipID = document.project.ensureClipForCurrentPattern(trackID: track.id)
            }
            let updated = SourceRef(
                mode: selectedSourceMode,
                generatorID: selectedPattern.sourceRef.generatorID,
                clipID: clipID,
                modifierGeneratorID: generator.id,
                modifierBypassed: false
            )
            document.project.setPatternSourceRef(updated, for: track.id, slotIndex: selectedPatternIndex)
        }
    }

    private func removeGeneratorSource() {
        guard let clipID = document.project.ensureClipForCurrentPattern(trackID: track.id) else {
            return
        }

        let updated = SourceRef(
            mode: .clip,
            generatorID: nil,
            clipID: clipID,
            modifierGeneratorID: selectedPattern.sourceRef.modifierGeneratorID,
            modifierBypassed: selectedPattern.sourceRef.modifierBypassed
        )
        document.project.setPatternSourceRef(updated, for: track.id, slotIndex: selectedPatternIndex)
    }

    private var selectedPatternIndexBinding: Binding<Int> {
        Binding(
            get: { document.project.selectedPatternIndex(for: track.id) },
            set: { document.project.setSelectedPatternIndex($0, for: track.id) }
        )
    }
}

private struct GeneratorSelectionSheet: View {
    let title: String
    let generators: [GeneratorPoolEntry]
    let onSelect: (GeneratorPoolEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            StudioTheme.stageFill
                .ignoresSafeArea()

            StudioPanel(title: title, eyebrow: "Choose a compatible generator for this slot.", accent: StudioTheme.cyan) {
                VStack(alignment: .leading, spacing: 12) {
                    if generators.isEmpty {
                        Text("No compatible generators are available.")
                            .studioText(.body)
                            .foregroundStyle(StudioTheme.mutedText)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(generators) { generator in
                                    Button {
                                        onSelect(generator)
                                        dismiss()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(generator.name)
                                                .studioText(.bodyBold)
                                                .foregroundStyle(StudioTheme.text)
                                            Text(generator.kind.label)
                                                .studioText(.label)
                                                .foregroundStyle(StudioTheme.mutedText)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                                                .stroke(StudioTheme.border, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 320)
                    }

                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.mutedText)
                }
            }
            .padding(24)
            .frame(minWidth: 520, minHeight: 360)
        }
    }
}
