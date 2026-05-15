import SwiftUI

enum TrackSourceModifierDisplayState: Equatable {
    case occupied
    case bypassed
    case empty
    case unavailable

    var badgeTitle: String {
        switch self {
        case .occupied:
            return "Mod"
        case .bypassed:
            return "Byp"
        case .empty:
            return "Empty"
        case .unavailable:
            return "N/A"
        }
    }

    static func supportsModifierStage(trackType: TrackType) -> Bool {
        GeneratorKind.allCases.contains {
            $0.compatibleWith.contains(trackType) && $0.supportsModifierStage
        }
    }

    static func resolve(
        trackType: TrackType,
        selectedGenerator: GeneratorPoolEntry?,
        isBypassed: Bool
    ) -> TrackSourceModifierDisplayState {
        if selectedGenerator != nil {
            return isBypassed ? .bypassed : .occupied
        }
        return supportsModifierStage(trackType: trackType) ? .empty : .unavailable
    }
}

struct TrackSourceModifierWell: View {
    let trackType: TrackType
    let selectedGenerator: GeneratorPoolEntry?
    let isBypassed: Bool
    let onShowGeneratorPicker: () -> Void
    let onToggleBypassed: () -> Void
    let onRemoveModifier: () -> Void

    private var displayState: TrackSourceModifierDisplayState {
        TrackSourceModifierDisplayState.resolve(
            trackType: trackType,
            selectedGenerator: selectedGenerator,
            isBypassed: isBypassed
        )
    }

    var body: some View {
        switch displayState {
        case .occupied, .bypassed:
            occupiedWell
        case .empty:
            emptyWell
        case .unavailable:
            unavailableWell
        }
    }

    @ViewBuilder
    private var occupiedWell: some View {
        if let selectedGenerator {
            slotWell(accent: isBypassed ? StudioTheme.amber : StudioTheme.violet) {
                modifierBadge(
                    title: displayState.badgeTitle,
                    accent: isBypassed ? StudioTheme.amber : StudioTheme.violet
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedGenerator.name)
                        .studioText(.bodyBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)

                    Text(selectedGenerator.kind.label)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer(minLength: 0)

                TrackSourceActionButton(title: "Choose", accent: StudioTheme.violet, action: onShowGeneratorPicker)
                TrackSourceActionButton(
                    title: isBypassed ? "Enable" : "Bypass",
                    accent: isBypassed ? StudioTheme.success : StudioTheme.amber,
                    action: onToggleBypassed
                )
                removeButton(action: onRemoveModifier)
            }
        } else {
            emptyWell
        }
    }

    private var emptyWell: some View {
        slotWell(accent: StudioTheme.violet) {
            modifierBadge(title: displayState.badgeTitle, accent: StudioTheme.violet)

            VStack(alignment: .leading, spacing: 3) {
                Text("No modifier selected")
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)

                Text("Add one to process the resolved source without creating source material.")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer(minLength: 0)

            TrackSourceActionButton(title: "[+] Add Modifier", accent: StudioTheme.violet, action: onShowGeneratorPicker)
        }
    }

    private var unavailableWell: some View {
        slotWell(accent: StudioTheme.border) {
            modifierBadge(title: displayState.badgeTitle, accent: StudioTheme.border)

            VStack(alignment: .leading, spacing: 3) {
                Text("Modifiers are unavailable for this track type")
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)

                Text("\(trackType.label) tracks cannot host modifier generators.")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer(minLength: 0)
        }
    }

    private func slotWell<Content: View>(
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            content()
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

    private func modifierBadge(title: String, accent: Color) -> some View {
        Text(title)
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

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("x")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(StudioTheme.text)
                .frame(width: 28, height: 28)
                .background(
                    Color.white.opacity(StudioOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .stroke(StudioTheme.border.opacity(StudioOpacity.ghostStroke), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove Modifier")
    }
}
