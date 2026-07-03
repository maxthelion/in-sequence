import SwiftUI

struct PitchAlgoEditor: View {
    let stage: PitchStage
    let inputClipChoices: [ClipPoolEntry]
    let harmonicSidechainClipChoices: [ClipPoolEntry]
    /// The one chrome accent of the hosting surface (track identity colour).
    var accent: Color = StudioTheme.cyan
    let onChange: (PitchStage) -> Void
    @State private var manualPitchDraft = ""

    private var kind: PitchAlgoKind { stage.algo.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Value selectors render through the studio grammar, never native
            // white pop-ups/segments (canon Rule 6, design review 22e/22f).
            StudioSegmentedControl(
                title: "Pitch Expander",
                selection: Binding(
                    get: { kind },
                    set: { onChange(PitchStage(algo: $0.defaultAlgo(clipChoices: inputClipChoices, current: stage.algo), harmonicSidechain: stage.harmonicSidechain)) }
                ),
                segments: PitchAlgoKind.allCases.map { kind in
                    StudioSegment(title: kind.title, value: kind)
                },
                accent: accent,
                layout: .init(fillsWidth: false, minWidth: 52)
            )

            StudioMenuPicker(
                title: "Harmonic Sidechain",
                selection: Binding(
                    get: { HarmonicSidechainPickerChoice(stage.harmonicSidechain, clipChoices: harmonicSidechainClipChoices) },
                    set: { onChange(PitchStage(algo: stage.algo, harmonicSidechain: $0.value)) }
                ),
                options: HarmonicSidechainPickerChoice.choices(from: harmonicSidechainClipChoices).map {
                    StudioMenuPickerOption(label: $0.title, value: $0)
                },
                help: "Harmonic source the pitch stage follows"
            )

            switch stage.algo {
            case let .manual(pitches, pickMode):
                VStack(alignment: .leading, spacing: 12) {
                    StudioSegmentedControl(
                        title: "Pick Mode",
                        selection: Binding(
                            get: { pickMode },
                            set: { onChange(PitchStage(algo: .manual(pitches: pitches, pickMode: $0), harmonicSidechain: stage.harmonicSidechain)) }
                        ),
                        segments: [
                            StudioSegment(title: "Sequential", value: PickMode.sequential),
                            StudioSegment(title: "Random", value: PickMode.random),
                        ],
                        accent: accent,
                        layout: .init(fillsWidth: false, minWidth: 84)
                    )

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
            case let .pool(root, scale, spread, selection, deviation):
                let normalizedSelection = selection.normalized
                let normalizedDeviation = deviation.normalized
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(PitchStage(
                            algo: .pool(root: $0, scale: scale, spread: spread, selection: normalizedSelection, deviation: normalizedDeviation),
                            harmonicSidechain: stage.harmonicSidechain
                        ))
                    }
                    scaleMenu(scale) {
                        onChange(PitchStage(
                            algo: .pool(root: root, scale: $0, spread: spread, selection: normalizedSelection, deviation: normalizedDeviation),
                            harmonicSidechain: stage.harmonicSidechain
                        ))
                    }
                    SourceParameterStepperRow(title: "Spread", value: spread, range: 0...36) {
                        onChange(PitchStage(
                            algo: .pool(root: root, scale: scale, spread: $0, selection: normalizedSelection, deviation: normalizedDeviation),
                            harmonicSidechain: stage.harmonicSidechain
                        ))
                    }

                    SourceParameterSliderRow(title: "Selection", value: (normalizedSelection.memory + 1) * 50, range: 0...100, accent: StudioTheme.violet) {
                        onChange(PitchStage(
                            algo: .pool(
                                root: root,
                                scale: scale,
                                spread: spread,
                                selection: PitchSelectionSettings(memory: ($0 / 50) - 1).normalized,
                                deviation: normalizedDeviation
                            ),
                            harmonicSidechain: stage.harmonicSidechain
                        ))
                    }

                    HStack(alignment: .top, spacing: 18) {
                        StudioRotaryKnob(
                            title: "Accidentals",
                            value: normalizedDeviation.accidentalChance * 100,
                            range: 0...100,
                            accent: StudioTheme.amber,
                            size: 56
                        ) {
                            onChange(PitchStage(
                                algo: .pool(
                                    root: root,
                                    scale: scale,
                                    spread: spread,
                                    selection: normalizedSelection,
                                    deviation: PitchDeviationSettings(
                                        accidentalChance: $0 / 100,
                                        octaveSpan: normalizedDeviation.octaveSpan,
                                        leadingChance: normalizedDeviation.leadingChance
                                    ).normalized
                                ),
                                harmonicSidechain: stage.harmonicSidechain
                            ))
                        }

                        StudioRotaryKnob(
                            title: "Octaves",
                            value: Double(normalizedDeviation.octaveSpan),
                            range: 0...3,
                            accent: StudioTheme.cyan,
                            size: 56
                        ) {
                            onChange(PitchStage(
                                algo: .pool(
                                    root: root,
                                    scale: scale,
                                    spread: spread,
                                    selection: normalizedSelection,
                                    deviation: PitchDeviationSettings(
                                        accidentalChance: normalizedDeviation.accidentalChance,
                                        octaveSpan: Int($0.rounded()),
                                        leadingChance: normalizedDeviation.leadingChance
                                    ).normalized
                                ),
                                harmonicSidechain: stage.harmonicSidechain
                            ))
                        }

                        StudioRotaryKnob(
                            title: "Leading",
                            value: normalizedDeviation.leadingChance * 100,
                            range: 0...100,
                            accent: StudioTheme.violet,
                            size: 56
                        ) {
                            onChange(PitchStage(
                                algo: .pool(
                                    root: root,
                                    scale: scale,
                                    spread: spread,
                                    selection: normalizedSelection,
                                    deviation: PitchDeviationSettings(
                                        accidentalChance: normalizedDeviation.accidentalChance,
                                        octaveSpan: normalizedDeviation.octaveSpan,
                                        leadingChance: $0 / 100
                                    ).normalized
                                ),
                                harmonicSidechain: stage.harmonicSidechain
                            ))
                        }
                    }
                }
            case let .randomInScale(root, scale, spread):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(PitchStage(algo: .randomInScale(root: $0, scale: scale, spread: spread), harmonicSidechain: stage.harmonicSidechain))
                    }
                    scaleMenu(scale) {
                        onChange(PitchStage(algo: .randomInScale(root: root, scale: $0, spread: spread), harmonicSidechain: stage.harmonicSidechain))
                    }
                    SourceParameterStepperRow(title: "Spread", value: spread, range: 0...36) {
                        onChange(PitchStage(algo: .randomInScale(root: root, scale: scale, spread: $0), harmonicSidechain: stage.harmonicSidechain))
                    }
                }
            case let .randomInChord(root, chord, inverted, spread):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(PitchStage(algo: .randomInChord(root: $0, chord: chord, inverted: inverted, spread: spread), harmonicSidechain: stage.harmonicSidechain))
                    }
                    StudioMenuPicker(
                        title: "Chord",
                        selection: Binding(
                            get: { chord },
                            set: { onChange(PitchStage(algo: .randomInChord(root: root, chord: $0, inverted: inverted, spread: spread), harmonicSidechain: stage.harmonicSidechain)) }
                        ),
                        options: ChordID.allCases.map { StudioMenuPickerOption(label: $0.displayName, value: $0) },
                        help: "Chord"
                    )
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
                    scaleMenu(scale) {
                        onChange(PitchStage(algo: .intervalProb(root: root, scale: $0, degreeWeights: degreeWeights), harmonicSidechain: stage.harmonicSidechain))
                    }
                    GridEditor(values: degreeWeights, allowedValues: [0.0, 0.25, 0.5, 0.75, 1.0], accent: StudioTheme.violet) { next in
                        onChange(PitchStage(algo: .intervalProb(root: root, scale: scale, degreeWeights: next), harmonicSidechain: stage.harmonicSidechain))
                    }
                }
            case let .markov(root, scale, styleID, leap, color):
                VStack(alignment: .leading, spacing: 12) {
                    SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                        onChange(PitchStage(algo: .markov(root: $0, scale: scale, styleID: styleID, leap: leap, color: color), harmonicSidechain: stage.harmonicSidechain))
                    }
                    scaleMenu(scale) {
                        onChange(PitchStage(algo: .markov(root: root, scale: $0, styleID: styleID, leap: leap, color: color), harmonicSidechain: stage.harmonicSidechain))
                    }
                    StudioMenuPicker(
                        title: "Style",
                        selection: Binding(
                            get: { styleID },
                            set: { onChange(PitchStage(algo: .markov(root: root, scale: scale, styleID: $0, leap: leap, color: color), harmonicSidechain: stage.harmonicSidechain)) }
                        ),
                        options: StyleProfileID.allCases.map { StudioMenuPickerOption(label: $0.displayName, value: $0) },
                        help: "Style profile"
                    )
                    SourceParameterSliderRow(title: "Leap", value: leap * 100, range: 0...100, accent: StudioTheme.amber) {
                        onChange(PitchStage(algo: .markov(root: root, scale: scale, styleID: styleID, leap: $0 / 100, color: color), harmonicSidechain: stage.harmonicSidechain))
                    }
                    SourceParameterSliderRow(title: "Color", value: color * 100, range: 0...100, accent: StudioTheme.violet) {
                        onChange(PitchStage(algo: .markov(root: root, scale: scale, styleID: styleID, leap: leap, color: $0 / 100), harmonicSidechain: stage.harmonicSidechain))
                    }
                }
            case let .fromClipPitches(clipID, pickMode):
                VStack(alignment: .leading, spacing: 12) {
                    StudioMenuPicker(
                        title: "Clip",
                        selection: Binding(
                            get: { Optional(clipID) },
                            set: { newValue in
                                guard let newValue else { return }
                                onChange(PitchStage(algo: .fromClipPitches(clipID: newValue, pickMode: pickMode), harmonicSidechain: stage.harmonicSidechain))
                            }
                        ),
                        options: inputClipChoices.map { StudioMenuPickerOption(label: $0.name, value: Optional($0.id)) },
                        help: "Source clip for pitches"
                    )

                    StudioSegmentedControl(
                        title: "Pick Mode",
                        selection: Binding(
                            get: { pickMode },
                            set: { onChange(PitchStage(algo: .fromClipPitches(clipID: clipID, pickMode: $0), harmonicSidechain: stage.harmonicSidechain)) }
                        ),
                        segments: [
                            StudioSegment(title: "Sequential", value: PickMode.sequential),
                            StudioSegment(title: "Random", value: PickMode.random),
                        ],
                        accent: accent,
                        layout: .init(fillsWidth: false, minWidth: 84)
                    )
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

                    StudioSegmentedControl(
                        title: "Hold Mode",
                        selection: Binding(
                            get: { holdMode },
                            set: { onChange(PitchStage(algo: .external(port: port, channel: channel, holdMode: $0), harmonicSidechain: stage.harmonicSidechain)) }
                        ),
                        segments: [
                            StudioSegment(title: "Pool", value: HoldMode.pool),
                            StudioSegment(title: "Latest", value: HoldMode.latest),
                        ],
                        accent: accent,
                        layout: .init(fillsWidth: false, minWidth: 64)
                    )
                }
            }
        }
    }

    /// Shared themed Scale menu (four algo cases carry one).
    private func scaleMenu(_ scale: ScaleID, onSelect: @escaping (ScaleID) -> Void) -> some View {
        StudioMenuPicker(
            title: "Scale",
            selection: Binding(get: { scale }, set: onSelect),
            options: ScaleID.allCases.map { StudioMenuPickerOption(label: $0.displayName, value: $0) },
            help: "Scale"
        )
    }
}

// MARK: - Display names (canon Rule 3 corollary: raw model/enum names never
// appear on screen — "minorPentatonic" reads as "Minor Pentatonic").

extension ScaleID {
    var displayName: String {
        switch self {
        case .chromatic: return "Chromatic"
        case .major: return "Major"
        case .naturalMinor: return "Natural Minor"
        case .harmonicMinor: return "Harmonic Minor"
        case .melodicMinor: return "Melodic Minor"
        case .majorPentatonic: return "Major Pentatonic"
        case .minorPentatonic: return "Minor Pentatonic"
        case .blues: return "Blues"
        case .dorian: return "Dorian"
        case .phrygian: return "Phrygian"
        case .lydian: return "Lydian"
        case .mixolydian: return "Mixolydian"
        case .locrian: return "Locrian"
        case .wholeTone: return "Whole Tone"
        case .diminished: return "Diminished"
        case .augmented: return "Augmented"
        case .gypsy: return "Gypsy"
        case .hungarianMinor: return "Hungarian Minor"
        case .akebono: return "Akebono"
        }
    }
}

extension ChordID {
    var displayName: String {
        switch self {
        case .majorTriad: return "Major"
        case .minorTriad: return "Minor"
        case .augmentedTriad: return "Augmented"
        case .diminishedTriad: return "Diminished"
        case .major7th: return "Major 7th"
        case .minor7th: return "Minor 7th"
        case .dominant7th: return "Dominant 7th"
        case .diminished7th: return "Diminished 7th"
        case .augmented7th: return "Augmented 7th"
        case .halfDiminished7th: return "Half-Diminished 7th"
        case .major6th: return "Major 6th"
        case .minor6th: return "Minor 6th"
        case .major9th: return "Major 9th"
        case .minor9th: return "Minor 9th"
        case .major11th: return "Major 11th"
        case .minor11th: return "Minor 11th"
        }
    }
}

extension StyleProfileID {
    var displayName: String {
        switch self {
        case .vocal: return "Vocal"
        case .balanced: return "Balanced"
        case .jazz: return "Jazz"
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
