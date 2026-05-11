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

struct TrackSourceSourceWellPresentation: Equatable {
    let displayState: TrackSourceSourceDisplayState

    var occupiedAffordanceLabels: [String] {
        switch displayState {
        case .occupiedClip, .occupiedGenerator:
            return ["Remove Source"]
        case .empty:
            return []
        }
    }

    var emptyAffordanceLabels: [String] {
        displayState == .empty ? ["Add Source"] : []
    }
}

struct TrackSourceSourceWell: View {
    let sourceMode: TrackSourceMode
    let currentClip: ClipPoolEntry?
    let selectedGenerator: GeneratorPoolEntry?
    let accent: Color
    let onShowSourcePicker: () -> Void
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
        slotWell(accent: StudioTheme.success, isEmpty: false) {
            sourceBadge(title: displayState.badgeTitle, accent: StudioTheme.success)

            VStack(alignment: .leading, spacing: 3) {
                Text(currentClip?.name ?? "Unnamed Clip")
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)

                Text(clipMetadata)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer(minLength: 0)

            removeButton(action: onRemoveSource)
        }
    }

    private var generatorSourceWell: some View {
        slotWell(accent: accent, isEmpty: false) {
            sourceBadge(title: displayState.badgeTitle, accent: accent)

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedGenerator?.name ?? "Unnamed Generator")
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)

                Text(selectedGenerator?.kind.label ?? "Generator source")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer(minLength: 0)

            removeButton(action: onRemoveSource)
        }
    }

    private var emptySourceWell: some View {
        slotWell(accent: accent, isEmpty: true) {
            sourceBadge(title: displayState.badgeTitle, accent: StudioTheme.border)

            VStack(alignment: .leading, spacing: 3) {
                Text("No source selected")
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)

                Text("This selected slot stays silent until you add a clip or generator.")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer(minLength: 0)

            TrackSourceActionButton(title: "[+] Add Source", accent: accent, action: onShowSourcePicker)
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

    private func slotWell<Content: View>(
        accent: Color,
        isEmpty: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(
            accent.opacity(isEmpty ? StudioOpacity.subtleFill : StudioOpacity.selectedFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(
                    accent.opacity(isEmpty ? StudioOpacity.subtleStroke : StudioOpacity.ghostStroke),
                    style: StrokeStyle(lineWidth: 1.5, dash: isEmpty ? [6, 5] : [])
                )
        )
        .padding(.horizontal, 10)
        .padding(.top, 8)
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
        .accessibilityLabel("Remove Source")
    }
}
