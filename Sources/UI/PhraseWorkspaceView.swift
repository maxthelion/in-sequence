import SwiftUI

struct PhraseWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController

    @State private var selectedLayerID = "pattern"
    @State private var selectedBarPage = 0

    private let phraseColumnWidth: CGFloat = 150
    private let trackColumnWidth: CGFloat = 132
    private let gridSpacing: CGFloat = 10

    private var phrases: [PhraseModel] { document.model.phrases }
    private var tracks: [StepSequenceTrack] { document.model.tracks }
    private var layers: [PhraseLayerDefinition] { document.model.layers }
    private var selectedPhrase: PhraseModel { document.model.selectedPhrase }
    private var selectedTrack: StepSequenceTrack { document.model.selectedTrack }

    private var selectedLayer: PhraseLayerDefinition {
        document.model.layer(id: selectedLayerID)
            ?? layers.first
            ?? PhraseLayerDefinition.defaultSet(for: tracks).first!
    }

    private var selectedCell: PhraseCell {
        selectedPhrase.cell(for: selectedLayer.id, trackID: selectedTrack.id)
    }

    private var playbackPhraseIndex: Int? {
        guard engineController.isRunning, !phrases.isEmpty else {
            return nil
        }

        let totalBars = phrases.reduce(0) { $0 + max(1, $1.lengthBars) }
        guard totalBars > 0 else {
            return nil
        }

        let absoluteBar = Int(engineController.transportTickIndex) / max(1, selectedPhrase.stepsPerBar)
        var cycleBar = absoluteBar % totalBars

        for (index, phrase) in phrases.enumerated() {
            let phraseBars = max(1, phrase.lengthBars)
            if cycleBar < phraseBars {
                return index
            }
            cycleBar -= phraseBars
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(
                title: "Phrase Matrix",
                eyebrow: "Project-scoped layers across the top, phrases down the rows, one cell per track and layer.",
                accent: layerAccent(selectedLayer.id)
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    topBar
                    layerBar
                    matrix
                }
            }

            HStack(alignment: .top, spacing: 18) {
                StudioPanel(
                    title: "Cell Editor",
                    eyebrow: "\(selectedPhrase.name) • \(selectedTrack.name) • \(selectedLayer.name)",
                    accent: layerAccent(selectedLayer.id)
                ) {
                    cellEditor
                }

                StudioPanel(
                    title: "Live View",
                    eyebrow: "Current phrase and layer through the transport lens",
                    accent: StudioTheme.amber
                ) {
                    LiveWorkspaceView(document: $document, selectedLayerID: $selectedLayerID)
                }
            }
        }
        .padding(20)
        .onAppear {
            if document.model.layer(id: selectedLayerID) == nil {
                selectedLayerID = document.model.patternLayer?.id ?? layers.first?.id ?? "pattern"
            }
        }
        .onChange(of: selectedPhrase.id) {
            selectedBarPage = min(selectedBarPage, max(0, selectedPhrase.lengthBars - 1))
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            StudioMetricPill(title: "Transport", value: engineController.transportPosition, accent: StudioTheme.cyan)
            StudioMetricPill(title: "Mode", value: engineController.transportMode.label, accent: StudioTheme.amber)
            StudioMetricPill(title: "Layer", value: selectedLayer.name, accent: layerAccent(selectedLayer.id))
            StudioMetricPill(title: "Phrases", value: "\(phrases.count)", accent: StudioTheme.violet)
            StudioMetricPill(title: "Tracks", value: "\(tracks.count)", accent: StudioTheme.success)

            if let playbackPhraseIndex {
                StudioMetricPill(
                    title: "Now",
                    value: phrases[playbackPhraseIndex].name,
                    accent: StudioTheme.success
                )
            }

            Spacer()

            Button("Add Phrase") {
                document.model.appendPhrase()
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.cyan)

            Button("Duplicate") {
                document.model.duplicateSelectedPhrase()
            }
            .buttonStyle(.bordered)

            Button("Remove") {
                document.model.removeSelectedPhrase()
            }
            .buttonStyle(.bordered)
            .disabled(phrases.count == 1)
        }
    }

    private var layerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(layers) { layer in
                    Button {
                        selectedLayerID = layer.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(layer.name.uppercased())
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .tracking(0.9)
                                .foregroundStyle(StudioTheme.text)

                            Text(layerSubtitle(layer))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                        }
                        .frame(width: 180, alignment: .leading)
                        .padding(12)
                        .background(layerFill(layer, isSelected: selectedLayer.id == layer.id), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(layerAccent(layer.id).opacity(selectedLayer.id == layer.id ? 0.7 : 0.18), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var matrix: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: gridSpacing) {
                HStack(spacing: gridSpacing) {
                    Color.clear
                        .frame(width: phraseColumnWidth, height: 58)

                    ForEach(tracks, id: \.id) { track in
                        Button {
                            document.model.selectTrack(id: track.id)
                        } label: {
                            PhraseMatrixTrackHeaderCell(
                                track: track,
                                isSelected: selectedTrack.id == track.id,
                                accent: track.groupID == nil ? layerAccent(selectedLayer.id) : StudioTheme.success
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(width: trackColumnWidth)
                    }
                }

                ForEach(Array(phrases.enumerated()), id: \.element.id) { index, phrase in
                    HStack(alignment: .top, spacing: gridSpacing) {
                        PhraseMatrixPhraseCell(
                            phrase: phrase,
                            isSelected: document.model.selectedPhraseID == phrase.id,
                            isPlaying: playbackPhraseIndex == index
                        ) {
                            document.model.selectPhrase(id: phrase.id)
                        }
                        .frame(width: phraseColumnWidth)

                        ForEach(tracks, id: \.id) { track in
                            Button {
                                document.model.selectPhrase(id: phrase.id)
                                document.model.selectTrack(id: track.id)
                            } label: {
                                PhraseGridCell(
                                    layer: selectedLayer,
                                    cell: phrase.cell(for: selectedLayer.id, trackID: track.id),
                                    phrase: phrase,
                                    track: track,
                                    isSelected: phrase.id == document.model.selectedPhraseID && track.id == document.model.selectedTrackID,
                                    accent: layerAccent(selectedLayer.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(width: trackColumnWidth)
                        }
                    }
                }
            }
            .padding(2)
        }
        .frame(minHeight: 280)
    }

    private var cellEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(selectedLayer.availableModes, id: \.self) { mode in
                    Button {
                        mutateSelectedPhrase { phrase in
                            phrase.setCellMode(mode, for: selectedLayer, trackID: selectedTrack.id)
                        }
                    } label: {
                        Text(mode.label)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedCell.editMode == mode ? layerAccent(selectedLayer.id).opacity(0.2) : Color.white.opacity(0.04),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedCell.editMode == mode ? StudioTheme.text : StudioTheme.mutedText)
                }
            }

            switch selectedCell {
            case .inheritDefault:
                StudioPlaceholderTile(
                    title: "Using Track Default",
                    detail: cellSummary(selectedCell, layer: selectedLayer, phrase: selectedPhrase, track: selectedTrack),
                    accent: layerAccent(selectedLayer.id)
                )
            case let .single(value):
                singleValueEditor(value: value)
            case let .bars(values):
                barsEditor(values: values)
            case let .steps(values):
                stepsEditor(values: values)
            case let .curve(points):
                curveEditor(points: points)
            }
        }
    }

    @ViewBuilder
    private func singleValueEditor(value: PhraseCellValue) -> some View {
        switch selectedLayer.valueType {
        case .boolean:
            Toggle("Enabled", isOn: Binding(
                get: {
                    if case let .bool(isOn) = value.normalized(for: selectedLayer) { return isOn }
                    return false
                },
                set: { newValue in
                    mutateSelectedPhrase { phrase in
                        phrase.setCell(.single(.bool(newValue)), for: selectedLayer.id, trackID: selectedTrack.id)
                    }
                }
            ))
            .toggleStyle(.switch)
        case .patternIndex:
            PatternIndexPicker(
                selectedIndex: Binding(
                    get: {
                        if case let .index(index) = value.normalized(for: selectedLayer) { return index }
                        return 0
                    },
                    set: { newIndex in
                        mutateSelectedPhrase { phrase in
                            phrase.setCell(.single(.index(newIndex)), for: selectedLayer.id, trackID: selectedTrack.id)
                        }
                    }
                )
            )
        case .scalar:
            ScalarValueEditor(
                title: selectedLayer.name,
                range: selectedLayer.scalarRange,
                value: Binding(
                    get: {
                        if case let .scalar(scalar) = value.normalized(for: selectedLayer) { return scalar }
                        return selectedLayer.minValue
                    },
                    set: { newValue in
                        mutateSelectedPhrase { phrase in
                            phrase.setCell(.single(.scalar(newValue)), for: selectedLayer.id, trackID: selectedTrack.id)
                        }
                    }
                )
            )
        }
    }

    @ViewBuilder
    private func barsEditor(values: [PhraseCellValue]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                HStack(spacing: 12) {
                    Text("Bar \(index + 1)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                        .frame(width: 44, alignment: .leading)

                    valueEditor(for: value) { newValue in
                        var nextValues = values
                        nextValues[index] = newValue
                        mutateSelectedPhrase { phrase in
                            phrase.setCell(.bars(nextValues), for: selectedLayer.id, trackID: selectedTrack.id)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stepsEditor(values: [PhraseCellValue]) -> some View {
        let pageCount = max(1, selectedPhrase.lengthBars)
        let activePage = min(selectedBarPage, pageCount - 1)
        let start = activePage * selectedPhrase.stepsPerBar
        let end = min(start + selectedPhrase.stepsPerBar, values.count)

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
                            .background(index == activePage ? layerAccent(selectedLayer.id).opacity(0.2) : Color.white.opacity(0.04), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(start..<end, id: \.self) { stepIndex in
                    Button {
                        mutateSelectedPhrase { phrase in
                            var nextValues = values
                            nextValues[stepIndex] = cycleValue(nextValues[stepIndex])
                            phrase.setCell(.steps(nextValues), for: selectedLayer.id, trackID: selectedTrack.id)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text("\(stepIndex - start + 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                            Text(valueLabel(values[stepIndex], layer: selectedLayer))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(layerAccent(selectedLayer.id).opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func curveEditor(points: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(PhraseCurvePreset.allCases, id: \.self) { preset in
                    Button(preset.label) {
                        mutateSelectedPhrase { phrase in
                            phrase.setCell(.curve(preset.points(in: selectedLayer.scalarRange)), for: selectedLayer.id, trackID: selectedTrack.id)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            PhraseCurvePreview(points: points, range: selectedLayer.scalarRange, accent: layerAccent(selectedLayer.id))
                .frame(height: 120)
        }
    }

    @ViewBuilder
    private func valueEditor(
        for value: PhraseCellValue,
        onChange: @escaping (PhraseCellValue) -> Void
    ) -> some View {
        switch selectedLayer.valueType {
        case .boolean:
            Toggle("", isOn: Binding(
                get: {
                    if case let .bool(isOn) = value.normalized(for: selectedLayer) { return isOn }
                    return false
                },
                set: { onChange(.bool($0)) }
            ))
            .labelsHidden()
        case .patternIndex:
            PatternIndexPicker(
                selectedIndex: Binding(
                    get: {
                        if case let .index(index) = value.normalized(for: selectedLayer) { return index }
                        return 0
                    },
                    set: { onChange(.index($0)) }
                )
            )
        case .scalar:
            ScalarValueEditor(
                title: nil,
                range: selectedLayer.scalarRange,
                value: Binding(
                    get: {
                        if case let .scalar(scalar) = value.normalized(for: selectedLayer) { return scalar }
                        return selectedLayer.minValue
                    },
                    set: { onChange(.scalar($0)) }
                )
            )
        }
    }

    private func mutateSelectedPhrase(_ update: (inout PhraseModel) -> Void) {
        var phrase = document.model.selectedPhrase
        update(&phrase)
        document.model.selectedPhrase = phrase
    }

    private func cycleValue(_ value: PhraseCellValue) -> PhraseCellValue {
        switch selectedLayer.valueType {
        case .boolean:
            if case let .bool(isOn) = value.normalized(for: selectedLayer) {
                return .bool(!isOn)
            }
            return .bool(true)
        case .patternIndex:
            if case let .index(index) = value.normalized(for: selectedLayer) {
                return .index((index + 1) % TrackPatternBank.slotCount)
            }
            return .index(0)
        case .scalar:
            let current: Double
            if case let .scalar(scalar) = value.normalized(for: selectedLayer) {
                current = scalar
            } else {
                current = selectedLayer.minValue
            }
            let step = (selectedLayer.maxValue - selectedLayer.minValue) / 4
            let next = current + step
            if next > selectedLayer.maxValue {
                return .scalar(selectedLayer.minValue)
            }
            return .scalar(next)
        }
    }

    private func cellSummary(
        _ cell: PhraseCell,
        layer: PhraseLayerDefinition,
        phrase: PhraseModel,
        track: StepSequenceTrack
    ) -> String {
        switch cell {
        case .inheritDefault:
            return "Uses the track default for \(layer.name.lowercased()) on \(track.name)."
        case let .single(value):
            return "Whole phrase uses \(valueLabel(value, layer: layer))."
        case .bars:
            return "One authored value per bar across \(phrase.lengthBars) bars."
        case .steps:
            return "Per-step authoring across \(phrase.stepCount) steps."
        case .curve:
            return "Interpolated scalar curve over the phrase duration."
        }
    }
}

struct LiveWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Binding var selectedLayerID: String
    @Environment(EngineController.self) private var engineController

    private var selectedLayer: PhraseLayerDefinition {
        document.model.layer(id: selectedLayerID)
            ?? document.model.patternLayer
            ?? document.model.layers.first!
    }

    private var phrase: PhraseModel { document.model.selectedPhrase }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                StudioMetricPill(title: "Phrase", value: phrase.name, accent: StudioTheme.violet)
                StudioMetricPill(title: "Layer", value: selectedLayer.name, accent: accent)
                StudioMetricPill(title: "Mode", value: engineController.transportMode.label, accent: StudioTheme.amber)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(document.model.tracks, id: \.id) { track in
                    let cell = phrase.cell(for: selectedLayer.id, trackID: track.id)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(track.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)
                        Text(cell.editMode.label.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(accent)
                        Text(liveValueLabel(cell))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(accent.opacity(0.22), lineWidth: 1)
                    )
                }
            }
        }
    }

    private var accent: Color {
        switch selectedLayer.valueType {
        case .boolean:
            return StudioTheme.success
        case .patternIndex:
            return StudioTheme.violet
        case .scalar:
            return StudioTheme.cyan
        }
    }

    private func liveValueLabel(_ cell: PhraseCell) -> String {
        switch cell {
        case .inheritDefault:
            return "Default"
        case let .single(value):
            return valueLabel(value, layer: selectedLayer)
        case let .bars(values):
            return "\(values.count) Bars"
        case let .steps(values):
            return "\(values.count) Steps"
        case let .curve(points):
            return "\(points.count) Pt Curve"
        }
    }
}

private struct PhraseMatrixTrackHeaderCell: View {
    let track: StepSequenceTrack
    let isSelected: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)
            Text(track.trackType.label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background((isSelected ? accent.opacity(0.15) : Color.white.opacity(0.03)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(isSelected ? 0.6 : 0.12), lineWidth: 1)
        )
    }
}

private struct PhraseMatrixPhraseCell: View {
    let phrase: PhraseModel
    let isSelected: Bool
    let isPlaying: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                Text(phrase.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)

                Text("\(phrase.lengthBars) bars")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)

                if isPlaying {
                    Text("Playing")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.success)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background((isSelected ? StudioTheme.violet.opacity(0.14) : Color.white.opacity(0.03)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke((isPlaying ? StudioTheme.success : StudioTheme.violet).opacity(isSelected || isPlaying ? 0.6 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PhraseGridCell: View {
    let layer: PhraseLayerDefinition
    let cell: PhraseCell
    let phrase: PhraseModel
    let track: StepSequenceTrack
    let isSelected: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(cell.editMode.label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(accent)
                Spacer()
            }

            cellPreview

            Text(cellSummary(cell, layer: layer, phrase: phrase))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background((isSelected ? accent.opacity(0.15) : Color.white.opacity(0.03)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(isSelected ? 0.6 : 0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var cellPreview: some View {
        switch cell {
        case .inheritDefault:
            Text("Default")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)
        case let .single(value):
            previewText(valueLabel(value, layer: layer))
        case let .bars(values):
            if layer.valueType == .scalar {
                HStack(spacing: 4) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        let scalar = scalarValue(for: value.normalized(for: layer), layer: layer)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(accent.opacity(0.75))
                            .frame(height: max(8, 8 + (scalarRatio(scalar, layer: layer) * 24)))
                            .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 36, alignment: .bottom)
            } else {
                previewText("\(values.count) bars")
            }
        case let .steps(values):
            previewText("\(values.count) steps")
        case .curve:
            previewText("Curve")
        }
    }

    private func previewText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(StudioTheme.text)
    }
}

private struct ScalarValueEditor: View {
    let title: String?
    let range: ClosedRange<Double>
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                Text(formattedValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(width: 54, alignment: .trailing)
            }
        }
    }

    private var formattedValue: String {
        if range.upperBound <= 1.01 && range.lowerBound >= 0 {
            return "\(Int((value * 100).rounded()))%"
        }
        if range.lowerBound < 0 {
            return "\(Int(value.rounded()))"
        }
        return "\(Int(value.rounded()))"
    }
}

private struct PatternIndexPicker: View {
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<TrackPatternBank.slotCount, id: \.self) { index in
                    Button {
                        selectedIndex = index
                    } label: {
                        Text("P\(index + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(index == selectedIndex ? StudioTheme.violet.opacity(0.2) : Color.white.opacity(0.04), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PhraseCurvePreview: View {
    let points: [Double]
    let range: ClosedRange<Double>
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let sampled = (0..<64).map { index in
                    PhraseCurveSampler.sample(points: points, at: index, stepCount: 64, range: range)
                }

                for (index, value) in sampled.enumerated() {
                    let x = geometry.size.width * CGFloat(Double(index) / Double(max(1, sampled.count - 1)))
                    let yRatio = (value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound)
                    let y = geometry.size.height * CGFloat(1 - yRatio)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(accent, lineWidth: 3)
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private enum PhraseCurvePreset: CaseIterable {
    case flat
    case rise
    case fall
    case swell

    var label: String {
        switch self {
        case .flat:
            return "Flat"
        case .rise:
            return "Rise"
        case .fall:
            return "Fall"
        case .swell:
            return "Swell"
        }
    }

    func points(in range: ClosedRange<Double>) -> [Double] {
        let low = range.lowerBound
        let high = range.upperBound
        let mid = (low + high) / 2

        switch self {
        case .flat:
            return [mid, mid, mid, mid]
        case .rise:
            return [low, low, mid, high]
        case .fall:
            return [high, mid, low, low]
        case .swell:
            return [low, high, high, low]
        }
    }
}

private func layerAccent(_ layerID: String) -> Color {
    switch layerID {
    case "pattern", "brightness", "register":
        return StudioTheme.violet
    case "mute", "fill-flag":
        return StudioTheme.success
    case "tension", "transpose":
        return StudioTheme.amber
    default:
        return StudioTheme.cyan
    }
}

private func layerFill(_ layer: PhraseLayerDefinition, isSelected: Bool) -> Color {
    let accent = layerAccent(layer.id)
    return isSelected ? accent.opacity(0.16) : accent.opacity(0.05)
}

private func layerSubtitle(_ layer: PhraseLayerDefinition) -> String {
    switch layer.target {
    case .patternIndex:
        return "pattern slot"
    case .mute:
        return "track mute"
    case let .macroRow(name):
        return name
    case .blockParam:
        return "block param"
    case .voiceRouteOverride:
        return "voice route"
    }
}

private func valueLabel(_ value: PhraseCellValue, layer: PhraseLayerDefinition) -> String {
    switch value.normalized(for: layer) {
    case let .bool(isOn):
        return isOn ? "On" : "Off"
    case let .index(index):
        return "P\(index + 1)"
    case let .scalar(scalar):
        if layer.maxValue <= 1.01 && layer.minValue >= 0 {
            return "\(Int((scalar * 100).rounded()))%"
        }
        if layer.id == "transpose" {
            return "\(Int(scalar.rounded())) st"
        }
        return "\(Int(scalar.rounded()))"
    }
}

private func scalarValue(for value: PhraseCellValue, layer: PhraseLayerDefinition) -> Double {
    switch value.normalized(for: layer) {
    case let .scalar(scalar):
        return scalar
    case let .index(index):
        return Double(index)
    case let .bool(isOn):
        return isOn ? layer.maxValue : layer.minValue
    }
}

private func scalarRatio(_ value: Double, layer: PhraseLayerDefinition) -> Double {
    (value - layer.minValue) / max(0.0001, layer.maxValue - layer.minValue)
}

private func cellSummary(_ cell: PhraseCell, layer: PhraseLayerDefinition, phrase: PhraseModel) -> String {
    switch cell {
    case .inheritDefault:
        return "Default"
    case let .single(value):
        return valueLabel(value, layer: layer)
    case let .bars(values):
        return "\(values.count) bars"
    case let .steps(values):
        return "\(values.count) steps"
    case .curve:
        return "\(phrase.lengthBars) bar curve"
    }
}
