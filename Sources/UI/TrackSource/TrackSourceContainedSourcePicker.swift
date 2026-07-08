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
            return ""
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
    case secondaryRecovery
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

    fileprivate static let newBlankGeneratorAction = TrackSourceContainedSourcePickerActionPresentation(
        id: .createBlankGenerator,
        title: "New Blank Generator",
        detail: "Fastest recovery path for this slot.",
        role: .primaryRecovery
    )

    private static let selectGeneratorAction = TrackSourceContainedSourcePickerActionPresentation(
        id: .showGeneratorPool,
        title: "Generator Pool",
        detail: "Browse compatible pool entries in this editor.",
        role: .poolDisclosure
    )

    private static let newBlankClipRootAction = TrackSourceContainedSourcePickerActionPresentation(
        id: .createBlankClip,
        title: "New Blank Clip",
        detail: "Start this slot from an empty clip.",
        role: .secondaryRecovery
    )

    private static let newBlankClipEmptyPoolAction = TrackSourceContainedSourcePickerActionPresentation(
        id: .createBlankClip,
        title: "New Blank Clip",
        detail: "Recover from the empty clip pool without leaving this editor.",
        role: .primaryRecovery
    )

    private static let selectClipAction = TrackSourceContainedSourcePickerActionPresentation(
        id: .showClipPool,
        title: "Clip Pool",
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
            primary: newBlankClipRootAction,
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
                recoveryAction: newBlankClipEmptyPoolAction
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
        if step == .root {
            rootContent
        } else {
            StudioPanel(title: step.title, eyebrow: step.eyebrow, accent: accent) {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case .root:
                        EmptyView()
                    case .generatorPool:
                        generatorPoolContent
                    case .clipPool:
                        clipPoolContent
                    }

                    controlsRow
                }
            }
        }
    }

    private var rootContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                newClipWell
                blankGeneratorList
            }

            VStack(alignment: .leading, spacing: 14) {
                newClipWell
                blankGeneratorList
            }
        }
    }

    private var newClipWell: some View {
        StudioAddCard(
            label: "New Clip",
            accent: accent,
            minHeight: 148,
            backgroundColor: StudioTheme.background,
            help: "Create a blank clip"
        ) {
            onCreateBlankClip()
        }
        .frame(maxWidth: .infinity)
    }

    private var blankGeneratorList: some View {
        VStack(alignment: .leading, spacing: 10) {
            pickerActionButton(
                action: TrackSourceContainedSourcePickerPresentation.newBlankGeneratorAction,
                accent: accent,
                trigger: onCreateBlankGenerator
            )
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .padding(StudioMetrics.Spacing.standard)
        .background(
            StudioTheme.background,
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
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
                                accent: accent,
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
        // Canon Rule 3: no explainer prose on the surface — the group
        // description and the secondary action's instruction live in
        // tooltips; titles + affordances carry the surface.
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .help(group.description)

            pickerActionButton(
                action: group.primary,
                accent: primaryAccent,
                trigger: primaryAction
            )

            poolEntryButton(
                title: group.secondary.title,
                detail: nil,
                help: group.secondary.detail,
                accent: StudioTheme.border,
                action: secondaryAction
            )
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(
            StudioTheme.subtleFill,
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
            .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func emptyPoolMessage(
        emptyState: TrackSourceContainedSourcePickerEmptyStatePresentation,
        recoveryAccent: Color,
        recoveryAction: @escaping () -> Void
    ) -> some View {
        // Canon Rule 3: the empty-pool line is real state; the recovery
        // instruction is a tooltip on the recovery affordance, not prose.
        VStack(alignment: .leading, spacing: 12) {
            Text(emptyState.title)
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)

            TrackSourceActionButton(title: emptyState.recoveryAction.title, accent: recoveryAccent, action: recoveryAction)
                .help(emptyState.detail)
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
            return accent
        case .showGeneratorPool, .showClipPool:
            return StudioTheme.border
        }
    }

    private func pickerActionButton(
        action: TrackSourceContainedSourcePickerActionPresentation,
        accent: Color,
        trigger: @escaping () -> Void
    ) -> some View {
        // Canon Rule 3: the action instruction is a tooltip, not a subtitle.
        Button(action: trigger) {
            VStack(alignment: .leading, spacing: 6) {
                Text(action.title)
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioMetrics.Spacing.standard)
            .background(
                rootActionFill(for: action.role, accent: accent),
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
                .stroke(rootActionStroke(for: action.role, accent: accent), lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .help(action.detail)
    }

    /// Colour identifies, it never floods (ux-canon rule 12): action tiles
    /// stay neutral; the primary action reads from its accent outline.
    private func rootActionFill(
        for role: TrackSourceContainedSourcePickerActionRole,
        accent: Color
    ) -> Color {
        StudioTheme.subtleFill
    }

    private func rootActionStroke(
        for role: TrackSourceContainedSourcePickerActionRole,
        accent: Color
    ) -> Color {
        switch role {
        case .primaryRecovery:
            return accent.opacity(StudioOpacity.ghostStroke)
        case .secondaryRecovery, .poolDisclosure:
            return StudioTheme.border.opacity(StudioOpacity.ghostStroke)
        }
    }

    /// `detail` is for real metadata only (kind, bar count) — instructional
    /// sentences go in `help` (canon Rule 3).
    private func poolEntryButton(
        title: String,
        detail: String?,
        help: String = "",
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)

                if let detail {
                    Text(detail)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioMetrics.Spacing.comfortable)
            .background(
                StudioTheme.subtleFill,
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
                .stroke(accent.opacity(StudioOpacity.ghostStroke), lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func clipMetadata(for clip: ClipPoolEntry) -> String {
        let stepCount = clip.content.stepCount
        let barCount = max(1, (stepCount + 15) / 16)
        let barsLabel = barCount == 1 ? "1 bar" : "\(barCount) bars"
        return "\(clip.trackType.label) clip · \(barsLabel)"
    }
}
