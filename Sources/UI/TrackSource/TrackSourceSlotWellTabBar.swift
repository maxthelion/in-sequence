import SwiftUI

struct TrackSourceSlotWellTabBar: View {
    @Binding var selectedTab: TrackSourceEditorTab
    let sourceState: TrackSourceSourceDisplayState
    let modifierState: TrackSourceModifierDisplayState
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            slotButton(
                tab: .source,
                title: "Source",
                badgeTitle: sourceState.badgeTitle,
                badgeAccent: sourceBadgeAccent
            )

            slotButton(
                tab: .modifiers,
                title: "Modifier",
                badgeTitle: modifierState.badgeTitle,
                badgeAccent: modifierBadgeAccent
            )
        }
        .padding(.horizontal, 10)
    }

    private func slotButton(
        tab: TrackSourceEditorTab,
        title: String,
        badgeTitle: String,
        badgeAccent: Color
    ) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title.uppercased())
                        .studioText(.eyebrowBold)
                        .foregroundStyle(isSelected ? StudioTheme.text : StudioTheme.mutedText)
                        .tracking(0.8)

                    badge(title: badgeTitle, accent: badgeAccent)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)

                Rectangle()
                    .fill(isSelected ? badgeAccent : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                (isSelected ? badgeAccent.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill)),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(
                        isSelected ? badgeAccent.opacity(StudioOpacity.ghostStroke) : StudioTheme.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sourceBadgeAccent: Color {
        switch sourceState {
        case .occupiedClip:
            return StudioTheme.success
        case .occupiedGenerator:
            return accent
        case .empty:
            return StudioTheme.border
        }
    }

    private var modifierBadgeAccent: Color {
        switch modifierState {
        case .occupied:
            return StudioTheme.violet
        case .bypassed:
            return StudioTheme.amber
        case .empty, .unavailable:
            return StudioTheme.border
        }
    }

    private func badge(title: String, accent: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(StudioTheme.text)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(
                accent.opacity(StudioOpacity.selectedFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.ghostStroke), lineWidth: 1)
            )
    }
}
