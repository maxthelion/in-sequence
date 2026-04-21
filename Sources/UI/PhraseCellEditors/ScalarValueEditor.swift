import SwiftUI

struct ScalarValueEditor: View {
    let title: String?
    let range: ClosedRange<Double>
    @Binding var value: Double

    @StateObject private var control = ThrottledMixValue()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { displayedValue },
                        set: { updateLive($0) }
                    ),
                    in: range,
                    onEditingChanged: handleEditingChanged
                )
                Text(formattedValue)
                    .studioText(.bodyBold)
                    .frame(width: 54, alignment: .trailing)
            }
        }
    }

    private var displayedValue: Double {
        control.rendered(committed: value)
    }

    private var formattedValue: String {
        if range.upperBound <= 1.01 && range.lowerBound >= 0 {
            return "\(Int((displayedValue * 100).rounded()))%"
        }
        return "\(Int(displayedValue.rounded()))"
    }

    private func handleEditingChanged(_ isEditing: Bool) {
        if isEditing {
            if !control.isDragging {
                control.begin(with: value)
            }
            return
        }

        guard let final = control.commit() else { return }
        value = final
    }

    private func updateLive(_ value: Double) {
        if !control.isDragging {
            control.begin(with: self.value)
        }
        _ = control.update(value)
    }
}
