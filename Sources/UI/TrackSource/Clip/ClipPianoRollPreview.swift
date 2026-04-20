import SwiftUI

struct ClipPianoRollPreview: View {
    let lengthBars: Int
    let stepsPerBar: Int
    let notes: [ClipNote]

    private var totalSteps: Int { max(1, lengthBars * stepsPerBar) }
    private var pitchRange: ClosedRange<Int> {
        let pitches = notes.map(\.pitch)
        return (pitches.min() ?? 48)...(pitches.max() ?? 72)
    }

    var body: some View {
        GeometryReader { geometry in
            let pitchCount = max(1, pitchRange.upperBound - pitchRange.lowerBound + 1)
            let stepWidth = geometry.size.width / CGFloat(totalSteps)
            let noteHeight = geometry.size.height / CGFloat(pitchCount)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.03))

                VStack(spacing: 0) {
                    ForEach(Array(pitchRange.reversed()), id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.03))
                            .frame(height: noteHeight)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 0) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Rectangle()
                            .fill(index % stepsPerBar == 0 ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                            .frame(width: stepWidth)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                ForEach(notes) { note in
                    let yIndex = pitchRange.upperBound - note.pitch
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(StudioTheme.violet.opacity(0.82))
                        .frame(
                            width: max(stepWidth * CGFloat(note.lengthSteps) - 2, 6),
                            height: max(noteHeight - 3, 6)
                        )
                        .offset(
                            x: stepWidth * CGFloat(note.startStep) + 1,
                            y: noteHeight * CGFloat(yIndex) + 1.5
                        )
                }
            }
        }
    }
}
