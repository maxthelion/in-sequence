import SwiftUI

struct ClipContentPreview: View {
    let content: ClipContent
    let onChange: ((ClipContent) -> Void)?

    init(content: ClipContent, onChange: ((ClipContent) -> Void)? = nil) {
        self.content = content
        self.onChange = onChange
    }

    var body: some View {
        switch content {
        case let .stepSequence(stepPattern, pitches):
            VStack(alignment: .leading, spacing: 14) {
                StepGridView(stepStates: stepPattern.map { $0 ? .on : .off }) { index in
                    guard let onChange else { return }
                    var nextPattern = stepPattern
                    guard nextPattern.indices.contains(index) else { return }
                    nextPattern[index].toggle()
                    onChange(.stepSequence(stepPattern: nextPattern, pitches: pitches))
                }
                .allowsHitTesting(onChange != nil)
            }
        case let .pianoRoll(lengthBars, stepsPerBar, notes):
            VStack(alignment: .leading, spacing: 14) {
                ClipPianoRollPreview(lengthBars: lengthBars, stepsPerBar: stepsPerBar, notes: notes)
                    .frame(height: 180)
                Text("\(notes.count) notes across \(lengthBars) bars")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
            }
        case let .sliceTriggers(stepPattern, sliceIndexes):
            VStack(alignment: .leading, spacing: 14) {
                StepGridView(stepStates: stepPattern.map { $0 ? .on : .off }) { index in
                    guard let onChange else { return }
                    var nextPattern = stepPattern
                    guard nextPattern.indices.contains(index) else { return }
                    nextPattern[index].toggle()
                    onChange(.sliceTriggers(stepPattern: nextPattern, sliceIndexes: sliceIndexes))
                }
                .allowsHitTesting(onChange != nil)

                TextField(
                    "Comma-separated slice indexes",
                    text: Binding(
                        get: { sliceIndexes.map(String.init).joined(separator: ", ") },
                        set: { newValue in
                            guard let onChange else { return }
                            let parsed = newValue
                                .split(separator: ",")
                                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                            if !parsed.isEmpty {
                                onChange(.sliceTriggers(stepPattern: stepPattern, sliceIndexes: parsed))
                            }
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }
}
