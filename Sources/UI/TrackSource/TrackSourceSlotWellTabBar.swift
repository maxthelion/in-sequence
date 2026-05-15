import SwiftUI

enum TrackSourceSlotWellTabAccentToken: Equatable {
    case trackAccent
    case success
    case violet
    case amber
    case border

    func color(trackAccent: Color) -> Color {
        switch self {
        case .trackAccent:
            return trackAccent
        case .success:
            return StudioTheme.success
        case .violet:
            return StudioTheme.violet
        case .amber:
            return StudioTheme.amber
        case .border:
            return StudioTheme.border
        }
    }
}

struct TrackSourceSlotWellTabAccentPresentation: Equatable {
    let badge: TrackSourceSlotWellTabAccentToken
    let selected: TrackSourceSlotWellTabAccentToken

    static func source(for state: TrackSourceSourceDisplayState) -> TrackSourceSlotWellTabAccentPresentation {
        switch state {
        case .occupiedClip:
            return TrackSourceSlotWellTabAccentPresentation(badge: .success, selected: .success)
        case .occupiedGenerator:
            return TrackSourceSlotWellTabAccentPresentation(badge: .trackAccent, selected: .trackAccent)
        case .empty:
            return TrackSourceSlotWellTabAccentPresentation(badge: .border, selected: .border)
        }
    }

    static func modifier(for state: TrackSourceModifierDisplayState) -> TrackSourceSlotWellTabAccentPresentation {
        switch state {
        case .occupied:
            return TrackSourceSlotWellTabAccentPresentation(badge: .violet, selected: .violet)
        case .bypassed:
            return TrackSourceSlotWellTabAccentPresentation(badge: .amber, selected: .amber)
        case .empty:
            return TrackSourceSlotWellTabAccentPresentation(badge: .border, selected: .violet)
        case .unavailable:
            return TrackSourceSlotWellTabAccentPresentation(badge: .border, selected: .border)
        }
    }
}

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
                accentPresentation: sourceAccentPresentation
            )

            slotButton(
                tab: .modifiers,
                title: "Modifier",
                badgeTitle: modifierState.badgeTitle,
                accentPresentation: modifierAccentPresentation
            )

            slotButton(
                tab: .clipHistory,
                title: "Clip History",
                badgeTitle: "Capture",
                accentPresentation: TrackSourceSlotWellTabAccentPresentation(badge: .success, selected: .success)
            )
        }
        .padding(.horizontal, 10)
    }

    private func slotButton(
        tab: TrackSourceEditorTab,
        title: String,
        badgeTitle: String,
        accentPresentation: TrackSourceSlotWellTabAccentPresentation
    ) -> some View {
        let isSelected = selectedTab == tab
        let badgeAccent = accentPresentation.badge.color(trackAccent: accent)
        let selectedAccent = accentPresentation.selected.color(trackAccent: accent)

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
                    .fill(isSelected ? selectedAccent : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                (isSelected ? selectedAccent.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill)),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(
                        isSelected ? selectedAccent.opacity(StudioOpacity.ghostStroke) : StudioTheme.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sourceAccentPresentation: TrackSourceSlotWellTabAccentPresentation {
        TrackSourceSlotWellTabAccentPresentation.source(for: sourceState)
    }

    private var modifierAccentPresentation: TrackSourceSlotWellTabAccentPresentation {
        TrackSourceSlotWellTabAccentPresentation.modifier(for: modifierState)
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
