import SwiftUI

struct SourceParameterStepperRow: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        HStack {
            Text(title.uppercased())
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
            Spacer()
            Stepper(value: Binding(get: { value }, set: onChange), in: range) {
                Text("\(value)")
                    .studioText(.bodyEmphasis)
                    .foregroundStyle(StudioTheme.text)
                    .monospacedDigit()
            }
        }
    }
}
