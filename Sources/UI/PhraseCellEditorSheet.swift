import SwiftUI

struct PhraseCellEditorTarget: Identifiable, Equatable {
    let phraseID: UUID
    let trackIDs: [UUID]
    let layerID: String

    init(phraseID: UUID, trackID: UUID, layerID: String) {
        self.phraseID = phraseID
        self.trackIDs = [trackID]
        self.layerID = layerID
    }

    init?(phraseID: UUID, trackIDs: [UUID], layerID: String) {
        var seenTrackIDs: Set<UUID> = []
        let uniqueTrackIDs = trackIDs.filter { seenTrackIDs.insert($0).inserted }
        guard !uniqueTrackIDs.isEmpty else { return nil }
        self.phraseID = phraseID
        self.trackIDs = uniqueTrackIDs
        self.layerID = layerID
    }

    var trackID: UUID { trackIDs[0] }

    var id: String {
        "\(phraseID.uuidString):\(trackIDs.map(\.uuidString).joined(separator: ",")):\(layerID)"
    }
}

enum PhraseAutomationSurfaceMode: String, CaseIterable, Hashable {
    case single
    case perBar
    case points

    var title: String {
        switch self {
        case .single: "Single"
        case .perBar: "Per Bar"
        case .points: "Points"
        }
    }

    func isAvailable(for editorKind: PhraseLayerEditorKind) -> Bool {
        self != .points || editorKind == .continuousScalar
    }

    static func mode(for cell: PhraseCell) -> PhraseAutomationSurfaceMode {
        switch cell {
        case .inheritDefault, .single:
            return .single
        case .bars:
            return .perBar
        case .steps, .curve:
            return .points
        }
    }
}

struct PhraseCellEditorSheet: View {
    let target: PhraseCellEditorTarget
    let accent: Color

    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @Environment(\.dismiss) private var dismiss

    private var phrase: PhraseModel? {
        session.store.phrases.first(where: { $0.id == target.phraseID }).map(session.phraseWithPerformOverlay)
    }

    private var track: StepSequenceTrack? {
        session.store.tracks.first(where: { $0.id == target.trackID })
    }

    private var targetTracks: [StepSequenceTrack] {
        target.trackIDs.compactMap { trackID in
            session.store.tracks.first(where: { $0.id == trackID })
        }
    }

    private var layer: PhraseLayerDefinition? {
        session.store.layer(id: target.layerID)
    }

    private var isTargetAvailable: Bool {
        phrase != nil && track != nil && layer != nil && targetTracks.count == target.trackIDs.count
    }

    var body: some View {
        Group {
            if let phrase, let track, let layer {
                StudioModal(
                    title: "Automation",
                    subtitle: automationSubtitle(phrase: phrase, track: track, layer: layer),
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

    private func automationSubtitle(
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) -> String {
        let trackLabel = target.trackIDs.count == 1 ? track.name : "\(target.trackIDs.count) cells"
        return "\(phrase.name) • \(trackLabel) • \(layer.name)"
    }

    @ViewBuilder
    private func cellEditor(phrase: PhraseModel, track: StepSequenceTrack, layer: PhraseLayerDefinition) -> some View {
        let cell = phrase.cell(for: layer.id, trackID: track.id)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                StudioSegmentedControl(
                    title: nil,
                    selection: Binding(
                        get: { PhraseAutomationSurfaceMode.mode(for: cell) },
                        set: { setSurfaceMode($0, phrase: phrase, track: track, layer: layer) }
                    ),
                    segments: PhraseAutomationSurfaceMode.allCases.map { mode in
                        StudioSegment(
                            title: mode.title,
                            value: mode,
                            isEnabled: mode.isAvailable(for: layer.editorKind),
                            help: mode == .points && layer.editorKind != .continuousScalar
                                ? "Points are available for continuous values"
                                : nil
                        )
                    },
                    accent: accent,
                    layout: .init(fillsWidth: false, minWidth: 76)
                )

                Spacer(minLength: 10)

                Button {
                    clearAutomation(phrase: phrase, track: track, layer: layer)
                } label: {
                    Label("Clear", systemImage: "xmark")
                        .studioText(.labelBold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(StudioTheme.subtleFill, in: Capsule())
                        .overlay(Capsule().stroke(cell.isAutomated ? accent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                }
                .buttonStyle(.plain)
                .foregroundStyle(cell.isAutomated ? StudioTheme.text : StudioTheme.mutedText)
                .disabled(!cell.isAutomated)
                .help(cell.isAutomated ? "Collapse automation to the value at the current phrase position" : "This cell has no automation to clear")
            }

            switch cell {
            case .inheritDefault:
                singleValueEditor(
                    value: layer.defaultValue(for: track.id),
                    phrase: phrase,
                    track: track,
                    layer: layer
                )
            case let .single(value):
                singleValueEditor(value: value, phrase: phrase, track: track, layer: layer)
            case let .bars(values):
                barsEditor(values: values, phrase: phrase, track: track, layer: layer)
            case let .steps(values):
                legacyStepsEditor(values: values, phrase: phrase, track: track, layer: layer)
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
                ),
                accent: accent
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
            HStack(spacing: 8) {
                Text("LOOP")
                    .studioText(.eyebrow)
                    .foregroundStyle(StudioTheme.mutedText)

                Text("\(values.count) bars")
                    .studioText(.labelBold)
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.text)

                StudioStepperButtons(
                    upHelp: "Add automation bar",
                    downHelp: "Remove automation bar",
                    isUpEnabled: values.count < phrase.lengthBars,
                    isDownEnabled: values.count > 1,
                    onUp: {
                        resizeBarAutomation(
                            values: values,
                            count: min(values.count + 1, phrase.lengthBars),
                            phrase: phrase,
                            track: track,
                            layer: layer
                        )
                    },
                    onDown: {
                        resizeBarAutomation(
                            values: values,
                            count: max(values.count - 1, 1),
                            phrase: phrase,
                            track: track,
                            layer: layer
                        )
                    }
                )

                Text("Phrase \(phrase.lengthBars) bars")
                    .studioText(.microEmphasis)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    barValueCell(index: index, value: value, layer: layer) { newValue in
                        var nextValues = values
                        nextValues[index] = newValue
                        setCell(.bars(nextValues), phrase: phrase, track: track, layer: layer)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func barValueCell(
        index: Int,
        value: PhraseCellValue,
        layer: PhraseLayerDefinition,
        onChange: @escaping (PhraseCellValue) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BAR \(index + 1)")
                .studioText(.eyebrow)
                .foregroundStyle(StudioTheme.mutedText)

            switch layer.valueType {
            case .boolean:
                let isOn = value.normalized(for: layer) == .bool(true)
                Button {
                    onChange(.bool(!isOn))
                } label: {
                    Text(isOn ? "On" : "Off")
                        .studioText(.labelBold)
                        .foregroundStyle(isOn ? StudioTheme.background : StudioTheme.text)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            isOn ? accent : StudioTheme.subtleFill,
                            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            case .patternIndex:
                let indexValue: Int = {
                    if case let .index(value) = value.normalized(for: layer) { return value }
                    return 0
                }()
                Button {
                    onChange(.index((indexValue + 1) % TrackPatternBank.slotCount))
                } label: {
                    Text("P\(indexValue + 1)")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.background)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Cycle pattern for bar \(index + 1)")
            case .scalar:
                let scalarValue: Double = {
                    if case let .scalar(value) = value.normalized(for: layer) { return value }
                    return layer.minValue
                }()
                Text(valueLabel(value, layer: layer))
                    .studioText(.microEmphasis)
                    .foregroundStyle(accent)
                StudioSlideControl(
                    value: scalarValue,
                    range: layer.scalarRange,
                    fillStyle: .fromLeading,
                    chrome: .roundedRectangle,
                    accent: accent,
                    help: "Bar \(index + 1) \(layer.name)",
                    onChange: { onChange(.scalar($0)) }
                )
                .frame(height: 28)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func curveEditor(
        points: [Double],
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("POINTS")
                    .studioText(.eyebrow)
                    .foregroundStyle(StudioTheme.mutedText)

                Text("\(points.count)")
                    .studioText(.labelBold)
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.text)

                StudioStepperButtons(
                    upHelp: "Add automation point",
                    downHelp: "Remove automation point",
                    isUpEnabled: points.count < 8,
                    isDownEnabled: points.count > 2,
                    onUp: {
                        guard points.count < 8 else { return }
                        setCell(.curve(addingCurvePoint(to: points)), phrase: phrase, track: track, layer: layer)
                    },
                    onDown: {
                        guard points.count > 2 else { return }
                        var next = points
                        next.remove(at: max(1, next.count - 2))
                        setCell(.curve(next), phrase: phrase, track: track, layer: layer)
                    }
                )

                Spacer(minLength: 8)

                ForEach(PhraseCurvePreset.allCases, id: \.self) { preset in
                    Button(preset.label) {
                        setCell(.curve(preset.points(in: layer.scalarRange)), phrase: phrase, track: track, layer: layer)
                    }
                    .buttonStyle(.plain)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                    )
                }
            }

            PhraseAutomationPointEditor(
                points: points,
                range: layer.scalarRange,
                accent: accent,
                onChange: { setCell(.curve($0), phrase: phrase, track: track, layer: layer) }
            )
            .frame(height: 220)
        }
    }

    private func legacyStepsEditor(
        values: [PhraseCellValue],
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) -> some View {
        let points = pointValues(fromLegacySteps: values, phrase: phrase, layer: layer)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("LEGACY STEPS")
                    .studioText(.eyebrow)
                    .foregroundStyle(StudioTheme.mutedText)
                Text("\(values.count)")
                    .studioText(.labelBold)
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.text)
                Spacer(minLength: 8)
                Button {
                    setCell(.curve(points), phrase: phrase, track: track, layer: layer)
                } label: {
                    Label("Convert to Points", systemImage: "point.3.connected.trianglepath.dotted")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.background)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            PhraseCurvePreview(points: points, range: layer.scalarRange, accent: accent)
                .frame(height: 180)
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
                ),
                accent: accent
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

    private func setSurfaceMode(
        _ mode: PhraseAutomationSurfaceMode,
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) {
        switch mode {
        case .single:
            clearAutomation(phrase: phrase, track: track, layer: layer)
        case .perBar:
            seedMode(.bars, phrase: phrase, layer: layer)
        case .points:
            guard layer.editorKind == .continuousScalar else { return }
            seedMode(.curve, phrase: phrase, layer: layer)
        }
    }

    private func resizeBarAutomation(
        values: [PhraseCellValue],
        count: Int,
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) {
        let safeCount = min(max(count, 1), max(1, phrase.lengthBars))
        let seed = values.isEmpty ? layer.defaultValue(for: track.id) : values[0]
        let resized = (0..<safeCount).map { index in
            values.isEmpty ? seed : values[index % values.count]
        }
        setCell(.bars(resized), phrase: phrase, track: track, layer: layer)
    }

    private func pointValues(
        fromLegacySteps values: [PhraseCellValue],
        phrase: PhraseModel,
        layer: PhraseLayerDefinition
    ) -> [Double] {
        let source = values.isEmpty ? [layer.defaultValue(for: target.trackID)] : values
        return (0..<max(2, phrase.stepCount)).map { index -> Double in
            let value = source[min(index, source.count - 1)]
            if case let .scalar(scalar) = value.normalized(for: layer) { return scalar }
            return layer.minValue
        }
    }

    private func addingCurvePoint(to points: [Double]) -> [Double] {
        guard let end = points.last else { return [0, 0] }
        guard points.count >= 2 else { return [end, end] }
        var next = points
        let previous = points[points.count - 2]
        next.insert((previous + end) / 2, at: points.count - 1)
        return next
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
            trackIDs: target.trackIDs,
            phraseID: phrase.id
        )
    }

    private func seedMode(
        _ mode: PhraseCellEditMode,
        phrase: PhraseModel,
        layer: PhraseLayerDefinition
    ) {
        let stepIndex = PhrasePlayhead(
            phrase: phrase,
            transportTickIndex: engineController.transportTickIndex
        ).stepIndex
        for trackID in target.trackIDs {
            let seed = phrase.resolvedValue(
                for: layer,
                trackID: trackID,
                stepIndex: stepIndex
            )
            let cell = PhraseCell.makeDefault(
                mode: mode,
                layer: layer,
                defaultValue: seed,
                stepCount: phrase.stepCount,
                barCount: phrase.lengthBars
            )
            session.setPhraseCell(
                cell,
                layerID: layer.id,
                trackIDs: [trackID],
                phraseID: phrase.id
            )
        }
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
        for trackID in target.trackIDs {
            session.setPhraseCell(
                phrase.clearingAutomation(for: layer, trackID: trackID, stepIndex: stepIndex),
                layerID: layer.id,
                trackIDs: [trackID],
                phraseID: phrase.id
            )
        }
    }

}
