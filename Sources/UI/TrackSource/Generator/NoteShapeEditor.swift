import SwiftUI

struct NoteShapeEditor: View {
    let shape: NoteShape
    var accent: Color = StudioTheme.transportAccent
    var knobSize: CGFloat = 56
    var spacing: CGFloat = 18
    let onChange: (NoteShape) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            StudioRotaryKnob(
                title: "Velocity",
                value: Double(shape.velocity),
                range: 1...127,
                accent: accent,
                size: knobSize
            ) { newValue in
                onChange(NoteShape(velocity: Int(newValue.rounded()), gateLength: shape.gateLength, accent: shape.accent))
            }

            StudioRotaryKnob(
                title: "Gate",
                value: Double(shape.gateLength),
                range: 1...16,
                accent: accent,
                size: knobSize
            ) { newValue in
                onChange(NoteShape(velocity: shape.velocity, gateLength: Int(newValue.rounded()), accent: shape.accent))
            }

            Spacer(minLength: 0)
        }
    }
}
