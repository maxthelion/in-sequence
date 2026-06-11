import SwiftUI

struct TrackSourceActionButton: View {
    let title: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.background)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
