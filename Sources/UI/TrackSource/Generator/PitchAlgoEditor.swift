import SwiftUI

struct PitchAlgoEditor: View {
    let stage: PitchStage
    let inputClipChoices: [ClipPoolEntry]
    let harmonicSidechainClipChoices: [ClipPoolEntry]
    /// The one chrome accent of the hosting surface (track identity colour).
    var accent: Color = StudioTheme.transportAccent
    let onChange: (PitchStage) -> Void

    private let pitchKnobSize: CGFloat = 64
    private let pitchColumns = Array(
        repeating: GridItem(.flexible(minimum: 64, maximum: 96), spacing: 14, alignment: .top),
        count: 8
    )

    private var poolStage: PitchStage {
        PitchStage(
            algo: stage.algo.normalizedForPitchGrammar,
            harmonicSidechain: stage.harmonicSidechain
        )
    }

    var body: some View {
        if case let .pool(root, scale, spread, selection, deviation) = poolStage.algo {
            let normalizedSelection = selection.normalized
            let normalizedDeviation = deviation.normalized

            VStack(alignment: .leading, spacing: 18) {
                PitchPoolKeyboardStrip(
                    availablePitchClasses: pitchPoolClasses(root: root, scale: scale, spread: spread),
                    accent: accent
                )

                scaleControl(scale) {
                    onChange(PitchStage(
                        algo: .pool(
                            root: root,
                            scale: $0,
                            spread: spread,
                            selection: normalizedSelection,
                            deviation: normalizedDeviation
                        ),
                        harmonicSidechain: poolStage.harmonicSidechain
                    ))
                }

                LazyVGrid(columns: pitchColumns, alignment: .leading, spacing: 16) {
                    StudioRotaryKnob(
                        title: "Root",
                        value: Double(root),
                        range: 0...127,
                        accent: accent,
                        size: pitchKnobSize
                    ) {
                        onChange(PitchStage(
                            algo: .pool(
                                root: Int($0.rounded()),
                                scale: scale,
                                spread: spread,
                                selection: normalizedSelection,
                                deviation: normalizedDeviation
                            ),
                            harmonicSidechain: poolStage.harmonicSidechain
                        ))
                    }

                    StudioRotaryKnob(
                        title: "Spread",
                        value: Double(spread),
                        range: 0...36,
                        accent: accent,
                        size: pitchKnobSize
                    ) {
                        onChange(PitchStage(
                            algo: .pool(
                                root: root,
                                scale: scale,
                                spread: Int($0.rounded()),
                                selection: normalizedSelection,
                                deviation: normalizedDeviation
                            ),
                            harmonicSidechain: poolStage.harmonicSidechain
                        ))
                    }

                    StudioRotaryKnob(
                        title: "Selection",
                        value: (normalizedSelection.memory + 1) * 50,
                        range: 0...100,
                        accent: accent,
                        size: pitchKnobSize
                    ) {
                        onChange(PitchStage(
                            algo: .pool(
                                root: root,
                                scale: scale,
                                spread: spread,
                                selection: PitchSelectionSettings(memory: ($0 / 50) - 1).normalized,
                                deviation: normalizedDeviation
                            ),
                            harmonicSidechain: poolStage.harmonicSidechain
                        ))
                    }

                    StudioRotaryKnob(
                        title: "Accidentals",
                        value: normalizedDeviation.accidentalChance * 100,
                        range: 0...100,
                        accent: accent,
                        size: pitchKnobSize
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
                            harmonicSidechain: poolStage.harmonicSidechain
                        ))
                    }

                    StudioRotaryKnob(
                        title: "Octaves",
                        value: Double(normalizedDeviation.octaveSpan),
                        range: 0...3,
                        accent: accent,
                        size: pitchKnobSize
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
                            harmonicSidechain: poolStage.harmonicSidechain
                        ))
                    }

                    StudioRotaryKnob(
                        title: "Leading",
                        value: normalizedDeviation.leadingChance * 100,
                        range: 0...100,
                        accent: accent,
                        size: pitchKnobSize
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
                            harmonicSidechain: poolStage.harmonicSidechain
                        ))
                    }
                }
            }
        }
    }

    /// Shared themed Scale menu (four algo cases carry one).
    private func scaleControl(_ scale: ScaleID, onSelect: @escaping (ScaleID) -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Scale")
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 52, alignment: .leading)

            ZStack {
                Menu {
                    ForEach(ScaleID.allCases, id: \.self) { option in
                        Button(option.displayName) {
                            onSelect(option)
                        }
                    }
                } label: {
                    Color.clear
                        .frame(height: 32)
                        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                HStack(spacing: 6) {
                    Text(scale.displayName)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    StudioTheme.subtleFill,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
                .allowsHitTesting(false)
            }
            .help("Scale")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pitchPoolClasses(root: Int, scale: ScaleID, spread: Int) -> Set<Int> {
        let filterClasses: Set<Int>
        switch poolStage.harmonicSidechain {
        case let .clip(clipID):
            let pitches = harmonicSidechainClipChoices.first(where: { $0.id == clipID })?.pitchPool ?? []
            filterClasses = Set(pitches.map { (($0 % 12) + 12) % 12 })
        case .none, .projectChordContext:
            filterClasses = []
        }

        return PitchAlgo.pitchPoolClasses(
            root: root,
            scaleID: scale,
            spread: spread,
            filterPitchClasses: filterClasses
        )
    }
}

private struct PitchPoolKeyboardStrip: View {
    let availablePitchClasses: Set<Int>
    let accent: Color

    private let labels = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private let whiteKeyClasses = [0, 2, 4, 5, 7, 9, 11]
    private let blackKeySpecs: [(pitchClass: Int, boundary: CGFloat)] = [
        (1, 1),
        (3, 2),
        (6, 4),
        (8, 5),
        (10, 6)
    ]

    var body: some View {
        GeometryReader { geometry in
            let whiteWidth = geometry.size.width / CGFloat(whiteKeyClasses.count)
            let blackWidth = min(52, max(32, whiteWidth * 0.72))

            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(whiteKeyClasses, id: \.self) { pitchClass in
                        whiteKey(for: pitchClass)
                            .frame(width: whiteWidth, height: 82)
                    }
                }

                ForEach(blackKeySpecs, id: \.pitchClass) { spec in
                    blackKey(for: spec.pitchClass)
                        .frame(width: blackWidth, height: 54)
                        .offset(x: whiteWidth * spec.boundary - blackWidth / 2)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82)
        .accessibilityLabel("Pitch pool keyboard")
        .accessibilityIdentifier("pitch-pool-keyboard")
    }

    private func whiteKey(for pitchClass: Int) -> some View {
        let isAvailable = availablePitchClasses.contains(pitchClass)

        return VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isAvailable ? accent : Color.clear)
                .frame(height: 7)
                .padding(.horizontal, 12)
                .padding(.top, 5)
                .padding(.bottom, 8)

            Spacer(minLength: 0)
            Text(labels[pitchClass])
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(isAvailable ? StudioTheme.text : StudioTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.bottom, 8)
        }
        .background(isAvailable ? StudioTheme.subtleFill : StudioTheme.background)
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 5,
                bottomLeadingRadius: 7,
                bottomTrailingRadius: 7,
                topTrailingRadius: 5,
                style: .continuous
            )
                .stroke(isAvailable ? accent : StudioTheme.border, lineWidth: isAvailable ? 2 : StudioMetrics.borderWidth)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 5,
                bottomLeadingRadius: 7,
                bottomTrailingRadius: 7,
                topTrailingRadius: 5,
                style: .continuous
            )
        )
        .accessibilityLabel(labels[pitchClass])
    }

    private func blackKey(for pitchClass: Int) -> some View {
        let isAvailable = availablePitchClasses.contains(pitchClass)

        return VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isAvailable ? accent : Color.clear)
                .frame(height: 6)
                .padding(.horizontal, 5)
                .padding(.top, 5)
                .padding(.bottom, 5)

            Spacer(minLength: 0)
            Text(labels[pitchClass])
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(isAvailable ? StudioTheme.text : StudioTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.bottom, 6)
        }
        .background(isAvailable ? StudioTheme.inset : StudioTheme.background)
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 4,
                bottomLeadingRadius: 5,
                bottomTrailingRadius: 5,
                topTrailingRadius: 4,
                style: .continuous
            )
                .stroke(isAvailable ? accent : StudioTheme.border, lineWidth: isAvailable ? 2 : StudioMetrics.borderWidth)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 4,
                bottomLeadingRadius: 5,
                bottomTrailingRadius: 5,
                topTrailingRadius: 4,
                style: .continuous
            )
        )
        .accessibilityLabel(labels[pitchClass])
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
