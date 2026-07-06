import SwiftUI

/// Pinned section header for scrolling pickers: uppercase eyebrow text.
struct StudioSectionHeader: View {
    let title: String
    var showsBackground = true

    var body: some View {
        Text(title.uppercased())
            .studioText(.eyebrow)
            .tracking(0.8)
            .foregroundStyle(StudioTheme.mutedText)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(showsBackground ? StudioTheme.background : Color.clear)
    }
}

/// Search field with leading magnifying glass on the standard subtle fill.
struct StudioSearchBar: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(StudioTheme.mutedText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
        .padding(StudioMetrics.Spacing.snug)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge))
    }
}

/// Compact empty-state row for inline lists (FX pickers, parameter lists)
/// where a full StudioPlaceholderTile would be too heavy.
struct StudioEmptyListRow: View {
    let message: String

    var body: some View {
        Text(message)
            .studioText(.label)
            .foregroundStyle(StudioTheme.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioMetrics.Spacing.compact)
    }
}
