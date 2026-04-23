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
    @Environment(SequencerDocumentSession.self) private var session
    let accent: Color

    @State private var selectedTab: TrackSourceEditorTab = .source
    @State private var generatorPickerPurpose: GeneratorPickerPurpose?

    private var project: Project { session.project }
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
    private var selectedSourceMode: TrackSourceMode { selectedPattern.sourceRef.mode }
    private var compatibleGenerators: [GeneratorPoolEntry] { project.compatibleGenerators(for: track) }
    private var generatedSourceInputClips: [ClipPoolEntry] { project.generatedSourceInputClips() }
    private var harmonicSidechainClips: [ClipPoolEntry] { project.harmonicSidechainClips() }
    private var currentClip: ClipPoolEntry? { project.clipEntry(id: selectedPattern.sourceRef.clipID) }
    private var selectedSourceGenerator: GeneratorPoolEntry? {
        project.generatorEntry(id: selectedPattern.sourceRef.generatorID)
    }
    private var selectedModifierGenerator: GeneratorPoolEntry? {
        project.generatorEntry(id: selectedPattern.sourceRef.modifierGeneratorID)
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
                    let generatorID = generator.id
                    session.mutateGenerator(id: generatorID) { entry in
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
                            session.setPatternModifierBypassed(
                                !selectedPattern.sourceRef.modifierBypassed,
                                for: track.id,
                                slotIndex: selectedPatternIndex
                            )
                        }
                        actionButton(title: "Remove Modifier", accent: StudioTheme.border) {
                            session.setPatternModifierGeneratorID(
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
                    let generatorID = generator.id
                    session.mutateGenerator(id: generatorID) { entry in
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
            VStack(alignment: .leading, spacing: 16) {
                ClipContentPreview(content: previewClipContent, defaultNote: defaultClipNote) { updated in
                    let trackID = track.id
                    session.ensureClipAndMutate(trackID: trackID) { _, entry in
                        entry.content = updated
                    }
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
                        let clipID = clip.id
                        session.mutateClip(id: clipID) { entry in
                            entry.macroLanes = updatedLanes
                        }
                    }
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
        let trackID = track.id
        switch purpose {
        case .source:
            let updated = SourceRef(
                mode: .generator,
                generatorID: generator.id,
                clipID: selectedPattern.sourceRef.clipID,
                modifierGeneratorID: selectedPattern.sourceRef.modifierGeneratorID,
                modifierBypassed: selectedPattern.sourceRef.modifierBypassed
            )
            session.setPatternSourceRef(updated, for: trackID, slotIndex: selectedPatternIndex)

        case .modifier:
            // For modifier selection, we may need to ensure a clip exists when the slot
            // is in clip mode without a clip ID yet. Use batch to handle both steps atomically.
            let currentPattern = selectedPattern
            let currentSourceMode = selectedSourceMode
            let slotIndex = selectedPatternIndex
            session.batch { s in
                var p = s.exportToProject()
                var clipID = currentPattern.sourceRef.clipID
                if currentSourceMode == .clip, clipID == nil {
                    clipID = p.ensureClipForCurrentPattern(trackID: trackID)
                    // Sync new clip into store if created.
                    let newClips = p.clipPool.filter { c in
                        s.exportToProject().clipPool.first(where: { $0.id == c.id }) == nil
                    }
                    for clip in newClips { s.appendClip(clip) }
                    for bank in p.patternBanks { s.setPatternBank(trackID: bank.trackID, bank: bank) }
                }
                let updated = SourceRef(
                    mode: currentSourceMode,
                    generatorID: currentPattern.sourceRef.generatorID,
                    clipID: clipID,
                    modifierGeneratorID: generator.id,
                    modifierBypassed: false
                )
                p.setPatternSourceRef(updated, for: trackID, slotIndex: slotIndex)
                for bank in p.patternBanks { s.setPatternBank(trackID: bank.trackID, bank: bank) }
            }
        }
    }

    private func removeGeneratorSource() {
        let trackID = track.id
        let currentPattern = selectedPattern
        let slotIndex = selectedPatternIndex
        session.batch { s in
            var p = s.exportToProject()
            guard let clipID = p.ensureClipForCurrentPattern(trackID: trackID) else { return }
            // Sync new clip if created.
            let newClips = p.clipPool.filter { c in
                s.exportToProject().clipPool.first(where: { $0.id == c.id }) == nil
            }
            for clip in newClips { s.appendClip(clip) }
            for bank in p.patternBanks { s.setPatternBank(trackID: bank.trackID, bank: bank) }
            let updated = SourceRef(
                mode: .clip,
                generatorID: nil,
                clipID: clipID,
                modifierGeneratorID: currentPattern.sourceRef.modifierGeneratorID,
                modifierBypassed: currentPattern.sourceRef.modifierBypassed
            )
            p.setPatternSourceRef(updated, for: trackID, slotIndex: slotIndex)
            for bank in p.patternBanks { s.setPatternBank(trackID: bank.trackID, bank: bank) }
        }
    }

    private var selectedPatternIndexBinding: Binding<Int> {
        Binding(
            get: { project.selectedPatternIndex(for: track.id) },
            set: { newValue in
                let trackID = track.id
                session.setSelectedPatternIndex(newValue, for: trackID)
            }
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
