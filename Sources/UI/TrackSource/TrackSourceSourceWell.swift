import SwiftUI

enum TrackSourceSourceDisplayState: Equatable {
    case occupiedClip
    case occupiedGenerator
    case empty

    var badgeTitle: String {
        switch self {
        case .occupiedClip:
            return "Clip"
        case .occupiedGenerator:
            return "Gen"
        case .empty:
            return "Empty"
        }
    }

    static func resolve(
        sourceMode: TrackSourceMode,
        currentClip: ClipPoolEntry?,
        selectedGenerator: GeneratorPoolEntry?
    ) -> TrackSourceSourceDisplayState {
        switch sourceMode {
        case .clip:
            return currentClip == nil ? .empty : .occupiedClip
        case .generator:
            return selectedGenerator == nil ? .empty : .occupiedGenerator
        }
    }
}

struct TrackSourceSourceWell: View {
    let sourceMode: TrackSourceMode
    let currentClip: ClipPoolEntry?
    let selectedGenerator: GeneratorPoolEntry?
    let accent: Color
    let onShowSourcePicker: () -> Void
    let onPresentClipHistory: () -> Void
    let onRemoveSource: () -> Void

    private var displayState: TrackSourceSourceDisplayState {
        TrackSourceSourceDisplayState.resolve(
            sourceMode: sourceMode,
            currentClip: currentClip,
            selectedGenerator: selectedGenerator
        )
    }

    var body: some View {
        switch displayState {
        case .occupiedClip:
            clipSourceWell
        case .occupiedGenerator:
            generatorSourceWell
        case .empty:
            emptySourceWell
        }
    }

    private var clipSourceWell: some View {
        StudioPanel(
            title: "Source Well",
            eyebrow: "Placement for the selected slot",
            accent: accent
        ) {
            VStack(alignment: .leading, spacing: 14) {
                sourceSummaryRow(
                    badgeTitle: displayState.badgeTitle,
                    accent: StudioTheme.success
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(currentClip?.name ?? "Unnamed Clip")
                            .studioText(.bodyBold)
                            .foregroundStyle(StudioTheme.text)

                        Text(clipMetadata)
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                }

                Text("This selected slot is sourcing notes from a clip.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TrackSourceActionButton(title: "Change Source", accent: accent, action: onShowSourcePicker)
                    TrackSourceActionButton(title: "Remove Source", accent: StudioTheme.border, action: onRemoveSource)
                }
            }
        }
    }

    private var generatorSourceWell: some View {
        StudioPanel(title: "Source Well", eyebrow: "Placement for the selected slot", accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                sourceSummaryRow(
                    badgeTitle: displayState.badgeTitle,
                    accent: accent
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedGenerator?.name ?? "Unnamed Generator")
                            .studioText(.bodyBold)
                            .foregroundStyle(StudioTheme.text)

                        Text(selectedGenerator?.kind.label ?? "Generator source")
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                }

                Text("This selected slot is using a generator as its source.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    TrackSourceActionButton(title: "Clip History...", accent: StudioTheme.success, action: onPresentClipHistory)
                    TrackSourceActionButton(title: "Change Source", accent: accent, action: onShowSourcePicker)
                    TrackSourceActionButton(title: "Remove Source", accent: StudioTheme.violet, action: onRemoveSource)
                }
            }
        }
    }

    private var emptySourceWell: some View {
        StudioPanel(title: "Source Well", eyebrow: "Placement for the selected slot", accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                sourceSummaryRow(
                    badgeTitle: displayState.badgeTitle,
                    accent: StudioTheme.border
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No source selected")
                            .studioText(.bodyBold)
                            .foregroundStyle(StudioTheme.text)

                        Text("Add a clip or generator for this slot.")
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                }

                Text("This selected slot stays silent until you add a source.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                TrackSourceActionButton(title: "[+] Add Source", accent: accent, action: onShowSourcePicker)
            }
        }
    }

    private var clipMetadata: String {
        guard let currentClip else {
            return "Clip source"
        }

        let stepCount = currentClip.content.stepCount
        let barCount = max(1, (stepCount + 15) / 16)
        let barsLabel = barCount == 1 ? "1 bar" : "\(barCount) bars"
        return "\(currentClip.trackType.label) clip · \(barsLabel)"
    }

    private func sourceSummaryRow<Content: View>(
        badgeTitle: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            sourceBadge(title: badgeTitle, accent: accent)
            content()
            Spacer(minLength: 0)
        }
    }

    private func sourceBadge(title: String, accent: Color) -> some View {
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
