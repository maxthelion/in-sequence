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
    @Binding var document: SeqAIDocument

    let target: PhraseCellEditorTarget
    let accent: Color

    @State private var selectedBarPage = 0
    @Environment(\.dismiss) private var dismiss

    private var phrase: PhraseModel? {
        document.project.phrases.first(where: { $0.id == target.phraseID })
    }

    private var track: StepSequenceTrack? {
        document.project.tracks.first(where: { $0.id == target.trackID })
    }

    private var layer: PhraseLayerDefinition? {
        document.project.layer(id: target.layerID)
    }

    private var isTargetAvailable: Bool {
        phrase != nil && track != nil && layer != nil
    }

    var body: some View {
        Group {
            if let phrase, let track, let layer {
                StudioPanel(
                    title: "Cell Editor",
                    eyebrow: "\(phrase.name) • \(track.name) • \(layer.name)",
                    accent: accent
                ) {
                    cellEditor(phrase: phrase, track: track, layer: layer)
                }
                .padding(24)
                .frame(minWidth: 680, minHeight: 420)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        dismiss()
                    }
            }
        }
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
                ForEach(layer.availableModes, id: \.self) { mode in
                    Button {
                        mutatePhrase(phraseID: phrase.id) { mutablePhrase in
                            mutablePhrase.setCellMode(mode, for: layer, trackID: track.id)
                        }
                    } label: {
                        Text(mode.label)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                cell.editMode == mode ? accent.opacity(0.2) : Color.white.opacity(0.04),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(cell.editMode == mode ? StudioTheme.text : StudioTheme.mutedText)
                }
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
                    mutatePhrase(phraseID: phrase.id) { mutablePhrase in
                        mutablePhrase.setCell(.single(.bool(newValue)), for: layer.id, trackID: track.id)
                    }
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
                        mutatePhrase(phraseID: phrase.id) { mutablePhrase in
                            mutablePhrase.setCell(.single(.index(newIndex)), for: layer.id, trackID: track.id)
                        }
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
                        mutatePhrase(phraseID: phrase.id) { mutablePhrase in
                            mutablePhrase.setCell(.single(.scalar(newValue)), for: layer.id, trackID: track.id)
                        }
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
                        mutatePhrase(phraseID: phrase.id) { mutablePhrase in
                            mutablePhrase.setCell(.bars(nextValues), for: layer.id, trackID: track.id)
                        }
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
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(index == activePage ? accent.opacity(0.2) : Color.white.opacity(0.04), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(start..<end, id: \.self) { stepIndex in
                    Button {
                        mutatePhrase(phraseID: phrase.id) { mutablePhrase in
                            var nextValues = values
                            nextValues[stepIndex] = cycledValue(nextValues[stepIndex], for: layer)
                            mutablePhrase.setCell(.steps(nextValues), for: layer.id, trackID: track.id)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text("\(stepIndex - start + 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                            Text(valueLabel(values[stepIndex], layer: layer))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(accent.opacity(0.25), lineWidth: 1)
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
                        mutatePhrase(phraseID: phrase.id) { mutablePhrase in
                            mutablePhrase.setCell(.curve(preset.points(in: layer.scalarRange)), for: layer.id, trackID: track.id)
                        }
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

    private func mutatePhrase(phraseID: UUID, _ update: (inout PhraseModel) -> Void) {
        document.project.updatePhrase(id: phraseID, update)
    }
}
