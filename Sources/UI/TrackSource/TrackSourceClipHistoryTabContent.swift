import SwiftUI

struct TrackSourceClipHistoryTabContent: View {
    let accent: Color
    let isAvailable: Bool
    let onPresentClipHistory: () -> Void

    var body: some View {
        TrackSourceSelectedWellBody(accent: accent, isEmpty: false) {
            HStack(alignment: .center, spacing: 12) {
                historyBadge

                VStack(alignment: .leading, spacing: 3) {
                    Text("Clip History")
                        .studioText(.bodyBold)
                        .foregroundStyle(StudioTheme.text)

                    Text("Recent output capture")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer(minLength: 0)

                if isAvailable {
                    TrackSourceActionButton(
                        title: "Clip History...",
                        accent: accent,
                        action: onPresentClipHistory
                    )
                } else {
                    Text("Generator source required")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .overlay(
                Rectangle()
                    .fill(accent.opacity(StudioOpacity.softStroke))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    private var historyBadge: some View {
        Text("History")
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(StudioTheme.text)
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .background(accent.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.ghostStroke), lineWidth: 1)
            )
    }
}
