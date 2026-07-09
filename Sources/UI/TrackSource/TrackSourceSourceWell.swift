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

    // One chrome accent per surface (locked Variant D): the Clip badge reads
    // "Clip" in the track identity colour — never a green state accent (the
    // 08-D mono-track prototype renders it in the surface accent).
    private var clipSourceWell: some View {
        slotWell(accent: accent) {
            sourceBadge(title: displayState.badgeTitle, accent: accent)

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
        slotWell(accent: accent) {
            sourceBadge(title: displayState.badgeTitle, accent: accent)

            VStack(alignment: .leading, spacing: 3) {
                Text(generatorDisplayName)
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
        slotWell(accent: accent) {
            sourceBadge(title: displayState.badgeTitle, accent: accent)

            Text("No source selected")
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)
                .help("This slot stays silent until you add a clip or generator")

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

    private var generatorDisplayName: String {
        guard let selectedGenerator else {
            return "Unnamed Generator"
        }

        let generatedNamePrefix = selectedGenerator.kind.label
        guard selectedGenerator.name.hasPrefix(generatedNamePrefix) else {
            return selectedGenerator.name
        }

        let suffix = selectedGenerator.name
            .dropFirst(generatedNamePrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.allSatisfy(\.isNumber) ? generatedNamePrefix : selectedGenerator.name
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

    private func sourceBadge(title: String, accent: Color) -> some View {
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
        .accessibilityLabel("Remove Source")
    }
}
