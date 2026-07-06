import SwiftUI

struct NoteShapeEditor: View {
    let shape: NoteShape
    var accent: Color = StudioTheme.transportAccent
    let onChange: (NoteShape) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            StudioRotaryKnob(
                title: "Velocity",
                value: Double(shape.velocity),
                range: 1...127,
                accent: accent
            ) { newValue in
                onChange(NoteShape(velocity: Int(newValue.rounded()), gateLength: shape.gateLength, accent: shape.accent))
            }

            StudioRotaryKnob(
                title: "Gate",
                value: Double(shape.gateLength),
                range: 1...16,
                accent: accent
            ) { newValue in
                onChange(NoteShape(velocity: shape.velocity, gateLength: Int(newValue.rounded()), accent: shape.accent))
            }

            Spacer(minLength: 0)
        }
    }
}
