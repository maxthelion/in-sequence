import SwiftUI

struct SourceParameterStepperRow: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
            Spacer()
            Stepper(value: Binding(get: { value }, set: onChange), in: range) {
                Text("\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
                    .monospacedDigit()
            }
        }
    }
}
