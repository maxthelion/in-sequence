import SwiftUI

struct PitchAlgoEditor: View {
    let pitch: PitchAlgo
    let clipChoices: [ClipPoolEntry]
    let onChange: (PitchAlgo) -> Void
    @State private var manualPitchDraft = ""

    private var kind: PitchAlgoKind { pitch.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(
                "Pitch Type",
                selection: Binding(
                    get: { kind },
                    set: { onChange($0.defaultAlgo(clipChoices: clipChoices, current: pitch)) }
                )
            ) {
                ForEach(PitchAlgoKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            switch pitch {
            case let .manual(pitches, pickMode):
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Pick Mode", selection: Binding(
                        get: { pickMode },
                        set: { onChange(.manual(pitches: pitches, pickMode: $0)) }
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
                                onChange(.manual(pitches: parsed, pickMode: pickMode))
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    WrapRow(items: pitches.map(String.init))
                }
            case let .randomInScale(root, scale, spread):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(.randomInScale(root: $0, scale: scale, spread: spread))
                    }
                    Picker("Scale", selection: Binding(
                        get: { scale },
                        set: { onChange(.randomInScale(root: root, scale: $0, spread: spread)) }
                    )) {
                        ForEach(ScaleID.allCases, id: \.self) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    SourceParameterStepperRow(title: "Spread", value: spread, range: 0...36) {
                        onChange(.randomInScale(root: root, scale: scale, spread: $0))
                    }
                }
            case let .randomInChord(root, chord, inverted, spread):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(.randomInChord(root: $0, chord: chord, inverted: inverted, spread: spread))
                    }
                    Picker("Chord", selection: Binding(
                        get: { chord },
                        set: { onChange(.randomInChord(root: root, chord: $0, inverted: inverted, spread: spread)) }
                    )) {
                        ForEach(ChordID.allCases, id: \.self) { chord in
                            Text(chord.rawValue).tag(chord)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("Inverted", isOn: Binding(
                        get: { inverted },
                        set: { onChange(.randomInChord(root: root, chord: chord, inverted: $0, spread: spread)) }
                    ))
                    .toggleStyle(.switch)
                    SourceParameterStepperRow(title: "Spread", value: spread, range: 0...36) {
                        onChange(.randomInChord(root: root, chord: chord, inverted: inverted, spread: $0))
                    }
                }
            case let .intervalProb(root, scale, degreeWeights):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(.intervalProb(root: $0, scale: scale, degreeWeights: degreeWeights))
                    }
                    Picker("Scale", selection: Binding(
                        get: { scale },
                        set: { onChange(.intervalProb(root: root, scale: $0, degreeWeights: degreeWeights)) }
                    )) {
                        ForEach(ScaleID.allCases, id: \.self) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    GridEditor(values: degreeWeights, allowedValues: [0.0, 0.25, 0.5, 0.75, 1.0], accent: StudioTheme.violet) { next in
                        onChange(.intervalProb(root: root, scale: scale, degreeWeights: next))
                    }
                }
            case let .markov(root, scale, styleID, leap, color):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(.markov(root: $0, scale: scale, styleID: styleID, leap: leap, color: color))
                    }
                    Picker("Scale", selection: Binding(
                        get: { scale },
                        set: { onChange(.markov(root: root, scale: $0, styleID: styleID, leap: leap, color: color)) }
                    )) {
                        ForEach(ScaleID.allCases, id: \.self) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Style", selection: Binding(
                        get: { styleID },
                        set: { onChange(.markov(root: root, scale: scale, styleID: $0, leap: leap, color: color)) }
                    )) {
                        ForEach(StyleProfileID.allCases, id: \.self) { styleID in
                            Text(styleID.rawValue).tag(styleID)
                        }
                    }
                    .pickerStyle(.menu)
                    SourceParameterSliderRow(title: "Leap", value: leap * 100, range: 0...100, accent: StudioTheme.amber) {
                        onChange(.markov(root: root, scale: scale, styleID: styleID, leap: $0 / 100, color: color))
                    }
                    SourceParameterSliderRow(title: "Color", value: color * 100, range: 0...100, accent: StudioTheme.violet) {
                        onChange(.markov(root: root, scale: scale, styleID: styleID, leap: leap, color: $0 / 100))
                    }
                }
            case let .fromClipPitches(clipID, pickMode):
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Clip", selection: Binding(
                        get: { Optional(clipID) },
                        set: { newValue in
                            guard let newValue else { return }
                            onChange(.fromClipPitches(clipID: newValue, pickMode: pickMode))
                        }
                    )) {
                        ForEach(clipChoices) { clip in
                            Text(clip.name).tag(Optional(clip.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Pick Mode", selection: Binding(
                        get: { pickMode },
                        set: { onChange(.fromClipPitches(clipID: clipID, pickMode: $0)) }
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
                        set: { onChange(.external(port: $0, channel: channel, holdMode: holdMode)) }
                    ))
                    .textFieldStyle(.roundedBorder)

                    SourceParameterStepperRow(title: "Channel", value: channel + 1, range: 1...16) {
                        onChange(.external(port: port, channel: $0 - 1, holdMode: holdMode))
                    }

                    Picker("Hold Mode", selection: Binding(
                        get: { holdMode },
                        set: { onChange(.external(port: port, channel: channel, holdMode: $0)) }
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
