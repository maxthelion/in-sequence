import SwiftUI

struct SourceParameterSliderRow: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let accent: Color
    let onChange: (Double) -> Void

    @StateObject private var control = ThrottledMixValue()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                Text("\(Int(displayedValue.rounded()))")
                    .studioText(.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.text)
            }

            Slider(
                value: Binding(
                    get: { displayedValue },
                    set: { updateLive($0) }
                ),
                in: range,
                onEditingChanged: handleEditingChanged
            )
            .tint(accent)
        }
    }

    private var displayedValue: Double {
        control.rendered(committed: value)
    }

    private func handleEditingChanged(_ isEditing: Bool) {
        if isEditing {
            if !control.isDragging {
                control.begin(with: value)
            }
            return
        }

        guard let final = control.commit() else { return }
        onChange(final)
    }

    private func updateLive(_ value: Double) {
        if !control.isDragging {
            control.begin(with: self.value)
        }
        _ = control.update(value)
    }
}
