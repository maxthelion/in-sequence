import SwiftUI

struct TrackSourceActionButton: View {
    let title: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(accent.opacity(StudioOpacity.selectedFill), in: Capsule())
                .overlay(Capsule().stroke(accent.opacity(StudioOpacity.ghostStroke), lineWidth: StudioMetrics.borderWidth))
        }
        .buttonStyle(.plain)
    }
}
