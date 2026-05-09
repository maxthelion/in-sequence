import SwiftUI

struct TrackSourceSlotWellTabBar: View {
    @Binding var selectedTab: TrackSourceEditorTab
    let sourceState: TrackSourceSourceDisplayState
    let modifierState: TrackSourceModifierDisplayState
    let currentClip: ClipPoolEntry?
    let selectedSourceGenerator: GeneratorPoolEntry?
    let selectedModifierGenerator: GeneratorPoolEntry?
    let trackType: TrackType
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            slotButton(
                tab: .source,
                title: "Source",
                badgeTitle: sourceState.badgeTitle,
                badgeAccent: sourceBadgeAccent,
                primaryText: sourcePrimaryText,
                detailText: sourceDetailText
            )

            slotButton(
                tab: .modifiers,
                title: "Modifier",
                badgeTitle: modifierState.badgeTitle,
                badgeAccent: modifierBadgeAccent,
                primaryText: modifierPrimaryText,
                detailText: modifierDetailText
            )
        }
    }

    private func slotButton(
        tab: TrackSourceEditorTab,
        title: String,
        badgeTitle: String,
        badgeAccent: Color,
        primaryText: String,
        detailText: String
    ) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            selectedTab = tab
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title.uppercased())
                        .studioText(.eyebrowBold)
                        .foregroundStyle(isSelected ? StudioTheme.text : StudioTheme.mutedText)
                        .tracking(0.8)

                    Spacer(minLength: 0)

                    badge(title: badgeTitle, accent: badgeAccent)
                }

                Text(primaryText)
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)

                Text(detailText)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .padding(12)
            .background(
                (isSelected ? badgeAccent.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill)),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(
                        isSelected ? badgeAccent.opacity(StudioOpacity.ghostStroke) : StudioTheme.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sourcePrimaryText: String {
        switch sourceState {
        case .occupiedClip:
            return currentClip?.name ?? "Clip source"
        case .occupiedGenerator:
            return selectedSourceGenerator?.name ?? "Generator source"
        case .empty:
            return "No source selected"
        }
    }

    private var sourceDetailText: String {
        switch sourceState {
        case .occupiedClip:
            return "Clip placed in this selected slot"
        case .occupiedGenerator:
            return selectedSourceGenerator?.kind.label ?? "Generator placed in this selected slot"
        case .empty:
            return "Add a clip or generator"
        }
    }

    private var modifierPrimaryText: String {
        switch modifierState {
        case .occupied:
            return selectedModifierGenerator?.name ?? "Modifier present"
        case .bypassed:
            return selectedModifierGenerator?.name ?? "Modifier bypassed"
        case .empty:
            return "No modifier selected"
        case .unavailable:
            return "Unavailable"
        }
    }

    private var modifierDetailText: String {
        switch modifierState {
        case .occupied:
            return selectedModifierGenerator?.kind.label ?? "Processes this selected slot"
        case .bypassed:
            return "Bypassed for this selected slot"
        case .empty:
            return "Add post-source processing"
        case .unavailable:
            return "\(trackType.label) tracks cannot host modifiers"
        }
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
            .padding(.vertical, 4)
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
