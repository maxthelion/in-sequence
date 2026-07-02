import SwiftUI

struct PhraseCellEditorTarget: Identifiable, Equatable {
    let phraseID: UUID
    let trackID: UUID
    let layerID: String

    var id: String {
        "\(phraseID.uuidString):\(trackID.uuidString):\(layerID)"
    }
}

struct PhraseCellEditorSheet: View {
    let target: PhraseCellEditorTarget
    let accent: Color

    @State private var selectedBarPage = 0
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @Environment(\.dismiss) private var dismiss

    private var phrase: PhraseModel? {
        session.store.phrases.first(where: { $0.id == target.phraseID }).map(session.phraseWithPerformOverlay)
    }

    private var track: StepSequenceTrack? {
        session.store.tracks.first(where: { $0.id == target.trackID })
    }

    private var layer: PhraseLayerDefinition? {
        session.store.layer(id: target.layerID)
    }

    private var isTargetAvailable: Bool {
        phrase != nil && track != nil && layer != nil
    }

    var body: some View {
        Group {
            if let phrase, let track, let layer {
                StudioModal(
                    title: "Automation",
                    subtitle: "\(phrase.name) • \(track.name) • \(layer.name)",
                    accent: accent,
                    minWidth: 680,
                    minHeight: 420,
                    onClose: { dismiss() }
                ) {
                    cellEditor(phrase: phrase, track: track, layer: layer)
                }
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        dismiss()
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isTargetAvailable) {
            if !isTargetAvailable {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func cellEditor(phrase: PhraseModel, track: StepSequenceTrack, layer: PhraseLayerDefinition) -> some View {
        let cell = phrase.cell(for: layer.id, trackID: track.id)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(availableModes(phrase: phrase, track: track, layer: layer), id: \.self) { mode in
                    Button {
                        setCellMode(mode, phrase: phrase, track: track, layer: layer)
                    } label: {
                        Text(mode.label)
                            .studioText(.labelBold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            // Colour identifies, it never floods (ux-canon rule
                            // 12): the selected mode is a fully solid accent
                            // thumb with a dark glyph, never a translucent wash.
                            .background(
                                cell.editMode == mode ? accent : Color.white.opacity(StudioOpacity.subtleFill),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(cell.editMode == mode ? StudioTheme.background : StudioTheme.mutedText)
                }

                Spacer(minLength: 10)

                Button {
                    clearAutomation(phrase: phrase, track: track, layer: layer)
                } label: {
                    Text("Clear Automation")
                        .studioText(.labelBold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                        .overlay(Capsule().stroke(cell.isAutomated ? accent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                }
                .buttonStyle(.plain)
                .foregroundStyle(cell.isAutomated ? StudioTheme.text : StudioTheme.mutedText)
                .disabled(!cell.isAutomated)
                .help(cell.isAutomated ? "Collapse automation to the value at the current phrase position" : "This cell has no automation to clear")
            }

            switch cell {
            case .inheritDefault:
                StudioPlaceholderTile(
                    title: "Using Track Default",
                    detail: cellSummary(cell, layer: layer, phrase: phrase),
                    accent: accent
                )
            case let .single(value):
                singleValueEditor(value: value, phrase: phrase, track: track, layer: layer)
            case let .bars(values):
                barsEditor(values: values, phrase: phrase, track: track, layer: layer)
            case let .steps(values):
                stepsEditor(values: values, phrase: phrase, track: track, layer: layer)
            case let .curve(points):
                curveEditor(points: points, phrase: phrase, track: track, layer: layer)
            }
        }
    }

    @ViewBuilder
    private func singleValueEditor(
        value: PhraseCellValue,
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) -> some View {
        switch layer.valueType {
        case .boolean:
            Toggle("Enabled", isOn: Binding(
                get: {
                    if case let .bool(isOn) = value.normalized(for: layer) { return isOn }
                    return false
                },
                set: { newValue in
                    setCell(.single(.bool(newValue)), phrase: phrase, track: track, layer: layer)
                }
            ))
            .toggleStyle(.switch)
        case .patternIndex:
            PatternIndexPicker(
                selectedIndex: Binding(
                    get: {
                        if case let .index(index) = value.normalized(for: layer) { return index }
                        return 0
                    },
                    set: { newIndex in
                        setCell(.single(.index(newIndex)), phrase: phrase, track: track, layer: layer)
                    }
                )
            )
        case .scalar:
            ScalarValueEditor(
                title: layer.name,
                range: layer.scalarRange,
                value: Binding(
                    get: {
                        if case let .scalar(scalar) = value.normalized(for: layer) { return scalar }
                        return layer.minValue
                    },
                    set: { newValue in
                        setCell(.single(.scalar(newValue)), phrase: phrase, track: track, layer: layer)
                    }
                )
            )
        }
    }

    @ViewBuilder
    private func barsEditor(
        values: [PhraseCellValue],
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                HStack(spacing: 12) {
                    Text("Bar \(index + 1)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                        .frame(width: 44, alignment: .leading)

                    valueEditor(for: value, layer: layer) { newValue in
                        var nextValues = values
                        nextValues[index] = newValue
                        setCell(.bars(nextValues), phrase: phrase, track: track, layer: layer)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stepsEditor(
        values: [PhraseCellValue],
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) -> some View {
        let pageCount = max(1, phrase.lengthBars)
        let activePage = min(selectedBarPage, pageCount - 1)
        let start = activePage * phrase.stepsPerBar
        let end = min(start + phrase.stepsPerBar, values.count)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Button {
                        selectedBarPage = index
                    } label: {
                        Text("Bar \(index + 1)")
                            .studioText(.eyebrowBold)
                            .foregroundStyle(index == activePage ? StudioTheme.background : StudioTheme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(index == activePage ? accent : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: StudioMetrics.Grid.matrixColumns(spacing: 8), spacing: 8) {
                ForEach(start..<end, id: \.self) { stepIndex in
                    Button {
                        var nextValues = values
                        nextValues[stepIndex] = cycledValue(nextValues[stepIndex], for: layer)
                        setCell(.steps(nextValues), phrase: phrase, track: track, layer: layer)
                    } label: {
                        VStack(spacing: 6) {
                            Text("\(stepIndex - start + 1)")
                                .studioText(.micro)
                                .foregroundStyle(StudioTheme.mutedText)
                            Text(valueLabel(values[stepIndex], layer: layer))
                                .studioText(.subtitle)
                                .foregroundStyle(StudioTheme.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                                .stroke(accent.opacity(0.25), lineWidth: StudioMetrics.borderWidth)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func curveEditor(
        points: [Double],
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(PhraseCurvePreset.allCases, id: \.self) { preset in
                    Button(preset.label) {
                        setCell(.curve(preset.points(in: layer.scalarRange)), phrase: phrase, track: track, layer: layer)
                    }
                    .buttonStyle(.bordered)
                }
            }

            PhraseCurvePreview(points: points, range: layer.scalarRange, accent: accent)
                .frame(height: 120)
        }
    }

    @ViewBuilder
    private func valueEditor(
        for value: PhraseCellValue,
        layer: PhraseLayerDefinition,
        onChange: @escaping (PhraseCellValue) -> Void
    ) -> some View {
        switch layer.valueType {
        case .boolean:
            Toggle("", isOn: Binding(
                get: {
                    if case let .bool(isOn) = value.normalized(for: layer) { return isOn }
                    return false
                },
                set: { onChange(.bool($0)) }
            ))
            .labelsHidden()
        case .patternIndex:
            PatternIndexPicker(
                selectedIndex: Binding(
                    get: {
                        if case let .index(index) = value.normalized(for: layer) { return index }
                        return 0
                    },
                    set: { onChange(.index($0)) }
                )
            )
        case .scalar:
            ScalarValueEditor(
                title: nil,
                range: layer.scalarRange,
                value: Binding(
                    get: {
                        if case let .scalar(scalar) = value.normalized(for: layer) { return scalar }
                        return layer.minValue
                    },
                    set: { onChange(.scalar($0)) }
                )
            )
        }
    }

    private func setCell(
        _ cell: PhraseCell,
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) {
        session.setPhraseCell(
            cell,
            layerID: layer.id,
            trackIDs: [track.id],
            phraseID: phrase.id
        )
    }

    private func setCellMode(
        _ mode: PhraseCellEditMode,
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) {
        let cell = PhraseCell.makeDefault(
            mode: mode,
            layer: layer,
            defaultValue: layer.defaultValue(for: track.id),
            stepCount: phrase.stepCount,
            barCount: phrase.lengthBars
        )
        setCell(cell, phrase: phrase, track: track, layer: layer)
    }

    private func clearAutomation(
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) {
        let stepIndex = PhrasePlayhead(
            phrase: phrase,
            transportTickIndex: engineController.transportTickIndex
        ).stepIndex
        setCell(
            phrase.clearingAutomation(for: layer, trackID: track.id, stepIndex: stepIndex),
            phrase: phrase,
            track: track,
            layer: layer
        )
    }

    /// Inherit is only offered when this cell follows a phrase whose same
    /// track/layer cell has an explicit value to inherit from.
    private func availableModes(
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) -> [PhraseCellEditMode] {
        var modes = layer.availableModes
        let phrases = session.store.phrases
        let hasPredecessorValue: Bool = {
            guard let index = phrases.firstIndex(where: { $0.id == phrase.id }), index > 0 else {
                return false
            }
            return phrases[index - 1].cell(for: layer.id, trackID: track.id).editMode != .inheritDefault
        }()
        if !hasPredecessorValue {
            modes.removeAll { $0 == .inheritDefault }
        }
        return modes
    }
}
