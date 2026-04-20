import SwiftUI

struct ScalarValueEditor: View {
    let title: String?
    let range: ClosedRange<Double>
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                Text(formattedValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(width: 54, alignment: .trailing)
            }
        }
    }

    private var formattedValue: String {
        if range.upperBound <= 1.01 && range.lowerBound >= 0 {
            return "\(Int((value * 100).rounded()))%"
        }
        return "\(Int(value.rounded()))"
    }
}
