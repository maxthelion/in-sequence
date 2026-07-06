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
    /// The ONE chrome accent of the surface (track identity colour). State
    /// (Mod/Byp/Empty) is carried by the badge TITLE, never a second colour.
    let accent: Color
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
            slotWell(accent: accent) {
                modifierBadge(
                    title: displayState.badgeTitle,
                    accent: accent
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

                TrackSourceActionButton(title: "Choose", accent: accent, action: onShowGeneratorPicker)
                TrackSourceActionButton(
                    title: isBypassed ? "Enable" : "Bypass",
                    accent: accent,
                    action: onToggleBypassed
                )
                removeButton(action: onRemoveModifier)
            }
        } else {
            emptyWell
        }
    }

    private var emptyWell: some View {
        slotWell(accent: accent) {
            modifierBadge(title: displayState.badgeTitle, accent: accent)

            Text("No modifier selected")
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)

            Spacer(minLength: 0)

            TrackSourceActionButton(title: "[+] Add Modifier", accent: accent, action: onShowGeneratorPicker)
                .help("Modifiers process the resolved source without creating source material")
        }
    }

    private var unavailableWell: some View {
        slotWell(accent: StudioTheme.border) {
            modifierBadge(title: displayState.badgeTitle, accent: StudioTheme.border)

            // State, not explanation (canon Rule 3): the "why" lives in the
            // tooltip; the badge already reads "N/A".
            Text("No modifier stage")
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)
                .help("\(trackType.label) tracks cannot host modifier generators")

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
                // A 1px divider STROKE drawn via fill (SwiftUI has no
                // bottom-border); softStroke is the stroke opacity token.
                // ux-canon-allow: hairline divider stroke, not a translucent accent wash
                .fill(accent.opacity(StudioOpacity.softStroke))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func modifierBadge(title: String, accent: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(StudioTheme.background)
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("x")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(StudioTheme.text)
                .frame(width: 28, height: 28)
                .background(
                    StudioTheme.subtleFill,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .stroke(StudioTheme.border.opacity(StudioOpacity.ghostStroke), lineWidth: StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove Modifier")
    }
}
