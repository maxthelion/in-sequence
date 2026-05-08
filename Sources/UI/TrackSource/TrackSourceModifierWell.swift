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
            StudioPanel(title: "Modifier", eyebrow: selectedGenerator.name, accent: StudioTheme.violet) {
                VStack(alignment: .leading, spacing: 14) {
                    modifierSummaryRow(
                        badgeTitle: displayState.badgeTitle,
                        accent: isBypassed ? StudioTheme.amber : StudioTheme.violet
                    ) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedGenerator.name)
                                .studioText(.bodyBold)
                                .foregroundStyle(StudioTheme.text)

                            Text(selectedGenerator.kind.label)
                                .studioText(.label)
                                .foregroundStyle(StudioTheme.mutedText)
                        }
                    }

                    Text(
                        isBypassed
                            ? "This modifier is bypassed. Re-enable it to hear its pitch processing."
                            : "Pitch processing runs after the selected source for this slot."
                    )
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        TrackSourceActionButton(title: "Choose Different Modifier", accent: StudioTheme.violet, action: onShowGeneratorPicker)
                        TrackSourceActionButton(
                            title: isBypassed ? "Enable" : "Bypass",
                            accent: isBypassed ? StudioTheme.success : StudioTheme.amber,
                            action: onToggleBypassed
                        )
                        TrackSourceActionButton(title: "Remove Modifier", accent: StudioTheme.border, action: onRemoveModifier)
                    }
                }
            }
        } else {
            emptyWell
        }
    }

    private var emptyWell: some View {
        StudioPanel(title: "Modifier", eyebrow: "Empty by default.", accent: StudioTheme.violet) {
            VStack(alignment: .leading, spacing: 14) {
                modifierSummaryRow(badgeTitle: displayState.badgeTitle, accent: StudioTheme.border) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No modifier selected")
                            .studioText(.bodyBold)
                            .foregroundStyle(StudioTheme.text)

                        Text("Add one to process the resolved source.")
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                }

                Text("This slot currently has no modifier. Adding one does not create source material.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                TrackSourceActionButton(title: "[+] Add Modifier", accent: StudioTheme.violet, action: onShowGeneratorPicker)
            }
        }
    }

    private var unavailableWell: some View {
        StudioPanel(title: "Modifier", eyebrow: "Unavailable for this track.", accent: StudioTheme.violet) {
            VStack(alignment: .leading, spacing: 14) {
                modifierSummaryRow(badgeTitle: displayState.badgeTitle, accent: StudioTheme.border) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Modifiers are unavailable for this track type")
                            .studioText(.bodyBold)
                            .foregroundStyle(StudioTheme.text)

                        Text("\(trackType.label) tracks cannot host modifier generators.")
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                }

                Text("Source editing remains available, but modifier actions are disabled for this selected slot.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func modifierSummaryRow<Content: View>(
        badgeTitle: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            modifierBadge(title: badgeTitle, accent: accent)
            content()
            Spacer(minLength: 0)
        }
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
}
