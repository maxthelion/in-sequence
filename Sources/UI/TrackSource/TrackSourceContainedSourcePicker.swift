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

enum TrackSourceContainedSourcePickerGroupID: Hashable {
    case generator
    case clip
}

enum TrackSourceContainedSourcePickerActionID: Equatable {
    case createBlankGenerator
    case showGeneratorPool
    case createBlankClip
    case showClipPool
}

enum TrackSourceContainedSourcePickerActionRole: Equatable {
    case primaryRecovery
    case poolDisclosure
}

struct TrackSourceContainedSourcePickerActionPresentation: Equatable {
    let id: TrackSourceContainedSourcePickerActionID
    let title: String
    let detail: String
    let role: TrackSourceContainedSourcePickerActionRole
}

struct TrackSourceContainedSourcePickerGroupPresentation: Equatable, Identifiable {
    let id: TrackSourceContainedSourcePickerGroupID
    let title: String
    let description: String
    let primary: TrackSourceContainedSourcePickerActionPresentation
    let secondary: TrackSourceContainedSourcePickerActionPresentation
}

struct TrackSourceContainedSourcePickerEmptyStatePresentation: Equatable {
    let title: String
    let detail: String
    let recoveryAction: TrackSourceContainedSourcePickerActionPresentation
}

struct TrackSourceContainedSourcePickerPresentation: Equatable {
    let step: TrackSourceContainedSourcePickerStep
    let rootGroups: [TrackSourceContainedSourcePickerGroupPresentation]
    let emptyState: TrackSourceContainedSourcePickerEmptyStatePresentation?

    static func resolve(
        step: TrackSourceContainedSourcePickerStep,
        compatibleGeneratorCount: Int,
        compatibleClipCount: Int
    ) -> TrackSourceContainedSourcePickerPresentation {
        TrackSourceContainedSourcePickerPresentation(
            step: step,
            rootGroups: step == .root ? Self.rootGroups : [],
            emptyState: Self.emptyState(
                for: step,
                compatibleGeneratorCount: compatibleGeneratorCount,
                compatibleClipCount: compatibleClipCount
            )
        )
    }

    private static let newBlankGeneratorAction = TrackSourceContainedSourcePickerActionPresentation(
        id: .createBlankGenerator,
        title: "New Blank Generator",
        detail: "Fastest recovery path for this slot.",
        role: .primaryRecovery
    )

    private static let selectGeneratorAction = TrackSourceContainedSourcePickerActionPresentation(
        id: .showGeneratorPool,
        title: "Select Generator From Pool",
        detail: "Browse compatible pool entries in this editor.",
        role: .poolDisclosure
    )

    private static let newBlankClipAction = TrackSourceContainedSourcePickerActionPresentation(
        id: .createBlankClip,
        title: "New Blank Clip",
        detail: "Fastest recovery path for this slot.",
        role: .primaryRecovery
    )

    private static let selectClipAction = TrackSourceContainedSourcePickerActionPresentation(
        id: .showClipPool,
        title: "Select Clip From Pool",
        detail: "Browse compatible pool entries in this editor.",
        role: .poolDisclosure
    )

    private static let rootGroups = [
        TrackSourceContainedSourcePickerGroupPresentation(
            id: .generator,
            title: "Generator",
            description: "Create a new blank generator quickly or switch to one already in the pool.",
            primary: newBlankGeneratorAction,
            secondary: selectGeneratorAction
        ),
        TrackSourceContainedSourcePickerGroupPresentation(
            id: .clip,
            title: "Clip",
            description: "Start from a fresh blank clip or reuse an existing compatible clip.",
            primary: newBlankClipAction,
            secondary: selectClipAction
        )
    ]

    private static func emptyState(
        for step: TrackSourceContainedSourcePickerStep,
        compatibleGeneratorCount: Int,
        compatibleClipCount: Int
    ) -> TrackSourceContainedSourcePickerEmptyStatePresentation? {
        switch step {
        case .root:
            return nil
        case .generatorPool:
            guard compatibleGeneratorCount == 0 else {
                return nil
            }
            return TrackSourceContainedSourcePickerEmptyStatePresentation(
                title: "No compatible generators are in the pool yet.",
                detail: "Create a blank generator to recover without leaving this source tab.",
                recoveryAction: newBlankGeneratorAction
            )
        case .clipPool:
            guard compatibleClipCount == 0 else {
                return nil
            }
            return TrackSourceContainedSourcePickerEmptyStatePresentation(
                title: "No compatible clips are in the pool yet.",
                detail: "Create a blank clip to recover without leaving this source tab.",
                recoveryAction: newBlankClipAction
            )
        }
    }
}

enum TrackSourceContainedSourcePickerNavigationAction: Equatable {
    case showRoot
    case showGeneratorPool
    case showClipPool
    case back
    case cancel
}

enum TrackSourceContainedSourcePickerNavigation {
    static func destination(
        from currentStep: TrackSourceContainedSourcePickerStep?,
        action: TrackSourceContainedSourcePickerNavigationAction
    ) -> TrackSourceContainedSourcePickerStep? {
        switch action {
        case .showRoot:
            return .root
        case .showGeneratorPool:
            return .generatorPool
        case .showClipPool:
            return .clipPool
        case .back:
            return currentStep == .root ? nil : .root
        case .cancel:
            return nil
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

    private var presentation: TrackSourceContainedSourcePickerPresentation {
        TrackSourceContainedSourcePickerPresentation.resolve(
            step: step,
            compatibleGeneratorCount: compatibleGenerators.count,
            compatibleClipCount: compatibleClips.count
        )
    }

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
            ForEach(presentation.rootGroups) { group in
                pickerGroup(
                    group: group,
                    primaryAccent: accent(for: group.primary.id),
                    primaryAction: action(for: group.primary.id),
                    secondaryAction: action(for: group.secondary.id)
                )
            }
        }
    }

    private var generatorPoolContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let emptyState = presentation.emptyState {
                emptyPoolMessage(
                    emptyState: emptyState,
                    recoveryAccent: accent(for: emptyState.recoveryAction.id),
                    recoveryAction: action(for: emptyState.recoveryAction.id)
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
            if let emptyState = presentation.emptyState {
                emptyPoolMessage(
                    emptyState: emptyState,
                    recoveryAccent: accent(for: emptyState.recoveryAction.id),
                    recoveryAction: action(for: emptyState.recoveryAction.id)
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
        group: TrackSourceContainedSourcePickerGroupPresentation,
        primaryAccent: Color,
        primaryAction: @escaping () -> Void,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)

            Text(group.description)
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            primaryPickerButton(
                title: group.primary.title,
                detail: group.primary.detail,
                accent: primaryAccent,
                action: primaryAction
            )

            poolEntryButton(
                title: group.secondary.title,
                detail: group.secondary.detail,
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
        emptyState: TrackSourceContainedSourcePickerEmptyStatePresentation,
        recoveryAccent: Color,
        recoveryAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(emptyState.title)
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)

            Text(emptyState.detail)
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            TrackSourceActionButton(title: emptyState.recoveryAction.title, accent: recoveryAccent, action: recoveryAction)
        }
    }

    private func action(for actionID: TrackSourceContainedSourcePickerActionID) -> () -> Void {
        switch actionID {
        case .createBlankGenerator:
            return onCreateBlankGenerator
        case .showGeneratorPool:
            return onShowGeneratorPool
        case .createBlankClip:
            return onCreateBlankClip
        case .showClipPool:
            return onShowClipPool
        }
    }

    private func accent(for actionID: TrackSourceContainedSourcePickerActionID) -> Color {
        switch actionID {
        case .createBlankGenerator:
            return accent
        case .createBlankClip:
            return StudioTheme.success
        case .showGeneratorPool, .showClipPool:
            return StudioTheme.border
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
