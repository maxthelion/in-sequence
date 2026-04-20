import SwiftUI

struct NoteShapeEditor: View {
    let shape: NoteShape
    let onChange: (NoteShape) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SourceParameterSliderRow(title: "Velocity", value: Double(shape.velocity), range: 1...127, accent: StudioTheme.amber) { newValue in
                onChange(NoteShape(velocity: Int(newValue.rounded()), gateLength: shape.gateLength, accent: shape.accent))
            }

            SourceParameterSliderRow(title: "Gate Length", value: Double(shape.gateLength), range: 1...16, accent: StudioTheme.violet) { newValue in
                onChange(NoteShape(velocity: shape.velocity, gateLength: Int(newValue.rounded()), accent: shape.accent))
            }
        }
    }
}
