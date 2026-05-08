import SwiftUI

enum TrackSourceContainedSourcePickerStep: Equatable {
    case root
    case generatorPool
    case clipPool

    var title: String {
        switch self {
        case .root:
            return "Add Source"
        case .generatorPool:
            return "Generator Pool"
        case .clipPool:
            return "Clip Pool"
        }
    }

    var eyebrow: String {
        switch self {
        case .root:
            return "Choose how to populate this slot."
        case .generatorPool:
            return "Pick a compatible generator without leaving the editor."
        case .clipPool:
            return "Pick a compatible clip without leaving the editor."
        }
    }
}

struct TrackSourceContainedSourcePicker: View {
    let step: TrackSourceContainedSourcePickerStep
    let accent: Color
    let compatibleGenerators: [GeneratorPoolEntry]
    let compatibleClips: [ClipPoolEntry]
    let onBack: () -> Void
    let onCancel: () -> Void
    let onShowGeneratorPool: () -> Void
    let onShowClipPool: () -> Void
    let onCreateBlankGenerator: () -> Void
    let onSelectGenerator: (GeneratorPoolEntry) -> Void
    let onCreateBlankClip: () -> Void
    let onSelectClip: (ClipPoolEntry) -> Void

    var body: some View {
        StudioPanel(title: step.title, eyebrow: step.eyebrow, accent: accent) {
            VStack(alignment: .leading, spacing: 16) {
                switch step {
                case .root:
                    rootContent
                case .generatorPool:
                    generatorPoolContent
                case .clipPool:
                    clipPoolContent
                }

                controlsRow
            }
        }
    }

    private var rootContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            pickerGroup(
                title: "Generator",
                description: "Create a new blank generator quickly or switch to one already in the pool.",
                primaryTitle: "New Blank Generator",
                primaryAccent: accent,
                primaryAction: onCreateBlankGenerator,
                secondaryTitle: "Select Generator From Pool",
                secondaryAction: onShowGeneratorPool
            )

            pickerGroup(
                title: "Clip",
                description: "Start from a fresh blank clip or reuse an existing compatible clip.",
                primaryTitle: "New Blank Clip",
                primaryAccent: StudioTheme.success,
                primaryAction: onCreateBlankClip,
                secondaryTitle: "Select Clip From Pool",
                secondaryAction: onShowClipPool
            )
        }
    }

    private var generatorPoolContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if compatibleGenerators.isEmpty {
                emptyPoolMessage(
                    title: "No compatible generators are in the pool yet.",
                    detail: "Create a blank generator to recover without leaving this source tab.",
                    recoveryTitle: "New Blank Generator",
                    recoveryAccent: accent,
                    recoveryAction: onCreateBlankGenerator
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(compatibleGenerators) { generator in
                            poolEntryButton(
                                title: generator.name,
                                detail: generator.kind.label,
                                accent: accent,
                                action: { onSelectGenerator(generator) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private var clipPoolContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if compatibleClips.isEmpty {
                emptyPoolMessage(
                    title: "No compatible clips are in the pool yet.",
                    detail: "Create a blank clip to recover without leaving this source tab.",
                    recoveryTitle: "New Blank Clip",
                    recoveryAccent: StudioTheme.success,
                    recoveryAction: onCreateBlankClip
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(compatibleClips) { clip in
                            poolEntryButton(
                                title: clip.name,
                                detail: clipMetadata(for: clip),
                                accent: StudioTheme.success,
                                action: { onSelectClip(clip) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            if step != .root {
                TrackSourceActionButton(title: "Back", accent: StudioTheme.border, action: onBack)
            }

            TrackSourceActionButton(title: "Cancel", accent: StudioTheme.border, action: onCancel)
        }
    }

    private func pickerGroup(
        title: String,
        description: String,
        primaryTitle: String,
        primaryAccent: Color,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)

            Text(description)
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            primaryPickerButton(
                title: primaryTitle,
                detail: "Fastest recovery path for this slot.",
                accent: primaryAccent,
                action: primaryAction
            )

            poolEntryButton(
                title: secondaryTitle,
                detail: "Browse compatible pool entries in this editor.",
                accent: StudioTheme.border,
                action: secondaryAction
            )
        }
        .padding(14)
        .background(
            Color.white.opacity(StudioOpacity.subtleFill),
            in: RoundedRectangle(
                cornerRadius: StudioMetrics.CornerRadius.panel,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: StudioMetrics.CornerRadius.panel,
                style: .continuous
            )
            .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private func emptyPoolMessage(
        title: String,
        detail: String,
        recoveryTitle: String,
        recoveryAccent: Color,
        recoveryAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)

            Text(detail)
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            TrackSourceActionButton(title: recoveryTitle, accent: recoveryAccent, action: recoveryAction)
        }
    }

    private func primaryPickerButton(
        title: String,
        detail: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)

                Text(detail)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                accent.opacity(StudioOpacity.selectedFill),
                in: RoundedRectangle(
                    cornerRadius: StudioMetrics.CornerRadius.control,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: StudioMetrics.CornerRadius.control,
                    style: .continuous
                )
                .stroke(accent.opacity(StudioOpacity.ghostStroke), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func poolEntryButton(
        title: String,
        detail: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)

                Text(detail)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(
                    cornerRadius: StudioMetrics.CornerRadius.control,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: StudioMetrics.CornerRadius.control,
                    style: .continuous
                )
                .stroke(accent.opacity(StudioOpacity.ghostStroke), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func clipMetadata(for clip: ClipPoolEntry) -> String {
        let stepCount = clip.content.stepCount
        let barCount = max(1, (stepCount + 15) / 16)
        let barsLabel = barCount == 1 ? "1 bar" : "\(barCount) bars"
        return "\(clip.trackType.label) clip · \(barsLabel)"
    }
}
