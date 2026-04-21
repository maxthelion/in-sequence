import SwiftUI

struct PitchAlgoEditor: View {
    let stage: PitchStage
    let inputClipChoices: [ClipPoolEntry]
    let harmonicSidechainClipChoices: [ClipPoolEntry]
    let onChange: (PitchStage) -> Void
    @State private var manualPitchDraft = ""

    private var kind: PitchAlgoKind { stage.algo.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(
                "Pitch Expander",
                selection: Binding(
                    get: { kind },
                    set: { onChange(PitchStage(algo: $0.defaultAlgo(clipChoices: inputClipChoices, current: stage.algo), harmonicSidechain: stage.harmonicSidechain)) }
                )
            ) {
                ForEach(PitchAlgoKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Picker("Harmonic Sidechain", selection: Binding(
                get: { HarmonicSidechainPickerChoice(stage.harmonicSidechain, clipChoices: harmonicSidechainClipChoices) },
                set: { onChange(PitchStage(algo: stage.algo, harmonicSidechain: $0.value)) }
            )) {
                ForEach(HarmonicSidechainPickerChoice.choices(from: harmonicSidechainClipChoices)) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.menu)

            switch stage.algo {
            case let .manual(pitches, pickMode):
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Pick Mode", selection: Binding(
                        get: { pickMode },
                        set: { onChange(PitchStage(algo: .manual(pitches: pitches, pickMode: $0), harmonicSidechain: stage.harmonicSidechain)) }
                    )) {
                        Text("Sequential").tag(PickMode.sequential)
                        Text("Random").tag(PickMode.random)
                    }
                    .pickerStyle(.segmented)

                    TextField("Comma-separated MIDI notes", text: Binding(
                        get: {
                            if manualPitchDraft.isEmpty {
                                return pitches.map(String.init).joined(separator: ", ")
                            }
                            return manualPitchDraft
                        },
                        set: { newValue in
                            manualPitchDraft = newValue
                            let parsed = newValue
                                .split(separator: ",")
                                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                                .filter { (0...127).contains($0) }

                            if !parsed.isEmpty {
                                onChange(PitchStage(algo: .manual(pitches: parsed, pickMode: pickMode), harmonicSidechain: stage.harmonicSidechain))
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    WrapRow(items: pitches.map(String.init))
                }
            case let .randomInScale(root, scale, spread):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(PitchStage(algo: .randomInScale(root: $0, scale: scale, spread: spread), harmonicSidechain: stage.harmonicSidechain))
                    }
                    Picker("Scale", selection: Binding(
                        get: { scale },
                        set: { onChange(PitchStage(algo: .randomInScale(root: root, scale: $0, spread: spread), harmonicSidechain: stage.harmonicSidechain)) }
                    )) {
                        ForEach(ScaleID.allCases, id: \.self) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    SourceParameterStepperRow(title: "Spread", value: spread, range: 0...36) {
                        onChange(PitchStage(algo: .randomInScale(root: root, scale: scale, spread: $0), harmonicSidechain: stage.harmonicSidechain))
                    }
                }
            case let .randomInChord(root, chord, inverted, spread):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(PitchStage(algo: .randomInChord(root: $0, chord: chord, inverted: inverted, spread: spread), harmonicSidechain: stage.harmonicSidechain))
                    }
                    Picker("Chord", selection: Binding(
                        get: { chord },
                        set: { onChange(PitchStage(algo: .randomInChord(root: root, chord: $0, inverted: inverted, spread: spread), harmonicSidechain: stage.harmonicSidechain)) }
                    )) {
                        ForEach(ChordID.allCases, id: \.self) { chord in
                            Text(chord.rawValue).tag(chord)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("Inverted", isOn: Binding(
                        get: { inverted },
                        set: { onChange(PitchStage(algo: .randomInChord(root: root, chord: chord, inverted: $0, spread: spread), harmonicSidechain: stage.harmonicSidechain)) }
                    ))
                    .toggleStyle(.switch)
                    SourceParameterStepperRow(title: "Spread", value: spread, range: 0...36) {
                        onChange(PitchStage(algo: .randomInChord(root: root, chord: chord, inverted: inverted, spread: $0), harmonicSidechain: stage.harmonicSidechain))
                    }
                }
            case let .intervalProb(root, scale, degreeWeights):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(PitchStage(algo: .intervalProb(root: $0, scale: scale, degreeWeights: degreeWeights), harmonicSidechain: stage.harmonicSidechain))
                    }
                    Picker("Scale", selection: Binding(
                        get: { scale },
                        set: { onChange(PitchStage(algo: .intervalProb(root: root, scale: $0, degreeWeights: degreeWeights), harmonicSidechain: stage.harmonicSidechain)) }
                    )) {
                        ForEach(ScaleID.allCases, id: \.self) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    GridEditor(values: degreeWeights, allowedValues: [0.0, 0.25, 0.5, 0.75, 1.0], accent: StudioTheme.violet) { next in
                        onChange(PitchStage(algo: .intervalProb(root: root, scale: scale, degreeWeights: next), harmonicSidechain: stage.harmonicSidechain))
                    }
                }
            case let .markov(root, scale, styleID, leap, color):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(PitchStage(algo: .markov(root: $0, scale: scale, styleID: styleID, leap: leap, color: color), harmonicSidechain: stage.harmonicSidechain))
                    }
                    Picker("Scale", selection: Binding(
                        get: { scale },
                        set: { onChange(PitchStage(algo: .markov(root: root, scale: $0, styleID: styleID, leap: leap, color: color), harmonicSidechain: stage.harmonicSidechain)) }
                    )) {
                        ForEach(ScaleID.allCases, id: \.self) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Style", selection: Binding(
                        get: { styleID },
                        set: { onChange(PitchStage(algo: .markov(root: root, scale: scale, styleID: $0, leap: leap, color: color), harmonicSidechain: stage.harmonicSidechain)) }
                    )) {
                        ForEach(StyleProfileID.allCases, id: \.self) { styleID in
                            Text(styleID.rawValue).tag(styleID)
                        }
                    }
                    .pickerStyle(.menu)
                    SourceParameterSliderRow(title: "Leap", value: leap * 100, range: 0...100, accent: StudioTheme.amber) {
                        onChange(PitchStage(algo: .markov(root: root, scale: scale, styleID: styleID, leap: $0 / 100, color: color), harmonicSidechain: stage.harmonicSidechain))
                    }
                    SourceParameterSliderRow(title: "Color", value: color * 100, range: 0...100, accent: StudioTheme.violet) {
                        onChange(PitchStage(algo: .markov(root: root, scale: scale, styleID: styleID, leap: leap, color: $0 / 100), harmonicSidechain: stage.harmonicSidechain))
                    }
                }
            case let .fromClipPitches(clipID, pickMode):
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Clip", selection: Binding(
                        get: { Optional(clipID) },
                        set: { newValue in
                            guard let newValue else { return }
                            onChange(PitchStage(algo: .fromClipPitches(clipID: newValue, pickMode: pickMode), harmonicSidechain: stage.harmonicSidechain))
                        }
                    )) {
                        ForEach(inputClipChoices) { clip in
                            Text(clip.name).tag(Optional(clip.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Pick Mode", selection: Binding(
                        get: { pickMode },
                        set: { onChange(PitchStage(algo: .fromClipPitches(clipID: clipID, pickMode: $0), harmonicSidechain: stage.harmonicSidechain)) }
                    )) {
                        Text("Sequential").tag(PickMode.sequential)
                        Text("Random").tag(PickMode.random)
                    }
                    .pickerStyle(.segmented)
                }
            case let .external(port, channel, holdMode):
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Port", text: Binding(
                        get: { port },
                        set: { onChange(PitchStage(algo: .external(port: $0, channel: channel, holdMode: holdMode), harmonicSidechain: stage.harmonicSidechain)) }
                    ))
                    .textFieldStyle(.roundedBorder)

                    SourceParameterStepperRow(title: "Channel", value: channel + 1, range: 1...16) {
                        onChange(PitchStage(algo: .external(port: port, channel: $0 - 1, holdMode: holdMode), harmonicSidechain: stage.harmonicSidechain))
                    }

                    Picker("Hold Mode", selection: Binding(
                        get: { holdMode },
                        set: { onChange(PitchStage(algo: .external(port: port, channel: channel, holdMode: $0), harmonicSidechain: stage.harmonicSidechain)) }
                    )) {
                        Text("Pool").tag(HoldMode.pool)
                        Text("Latest").tag(HoldMode.latest)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

private struct HarmonicSidechainPickerChoice: Hashable, Identifiable {
    let value: HarmonicSidechainSource
    let title: String

    var id: String {
        switch value {
        case .none:
            return "none"
        case .projectChordContext:
            return "project-chord-context"
        case let .clip(id):
            return "clip-\(id.uuidString)"
        }
    }

    init(_ value: HarmonicSidechainSource, clipChoices: [ClipPoolEntry] = []) {
        self.value = value
        switch value {
        case .none:
            self.title = "None"
        case .projectChordContext:
            self.title = "Chord Context"
        case let .clip(id):
            self.title = clipChoices.first(where: { $0.id == id })?.name ?? "Clip"
        }
    }

    static func choices(from clipChoices: [ClipPoolEntry]) -> [HarmonicSidechainPickerChoice] {
        [
            HarmonicSidechainPickerChoice(.none, clipChoices: clipChoices),
            HarmonicSidechainPickerChoice(.projectChordContext, clipChoices: clipChoices),
        ] + clipChoices.map { clip in
            HarmonicSidechainPickerChoice(.clip(clip.id), clipChoices: clipChoices)
        }
    }
}
