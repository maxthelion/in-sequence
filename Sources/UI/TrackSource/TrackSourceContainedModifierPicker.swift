import SwiftUI

enum TrackSourceContainedModifierPickerStep: Equatable {
    case root
    case modifierPool

    var title: String {
        switch self {
        case .root:
            return "Add Modifier"
        case .modifierPool:
            return "Modifier Pool"
        }
    }

    var eyebrow: String {
        switch self {
        case .root:
            return "Choose how to process this slot."
        case .modifierPool:
            return "Pick a compatible modifier without leaving the editor."
        }
    }
}

enum TrackSourceContainedModifierPickerActionID: Equatable {
    case createBlankModifier
    case showModifierPool
}

struct TrackSourceContainedModifierPickerPresentation: Equatable {
    let step: TrackSourceContainedModifierPickerStep
    let actions: [TrackSourceContainedModifierPickerActionID]
    let emptyStateTitle: String?

    static func resolve(
        step: TrackSourceContainedModifierPickerStep,
        compatibleModifierCount: Int
    ) -> TrackSourceContainedModifierPickerPresentation {
        TrackSourceContainedModifierPickerPresentation(
            step: step,
            actions: step == .root ? [.createBlankModifier, .showModifierPool] : [],
            emptyStateTitle: step == .modifierPool && compatibleModifierCount == 0
                ? "No compatible modifiers are in the pool yet."
                : nil
        )
    }
}

enum TrackSourceContainedModifierPickerNavigationAction: Equatable {
    case showRoot
    case showModifierPool
    case back
    case cancel
}

enum TrackSourceContainedModifierPickerNavigation {
    static func destination(
        from currentStep: TrackSourceContainedModifierPickerStep?,
        action: TrackSourceContainedModifierPickerNavigationAction
    ) -> TrackSourceContainedModifierPickerStep? {
        switch action {
        case .showRoot:
            return .root
        case .showModifierPool:
            return .modifierPool
        case .back:
            return currentStep == .root ? nil : .root
        case .cancel:
            return nil
        }
    }
}

struct TrackSourceContainedModifierPicker: View {
    let step: TrackSourceContainedModifierPickerStep
    let compatibleModifiers: [GeneratorPoolEntry]
    let onBack: () -> Void
    let onCancel: () -> Void
    let onShowModifierPool: () -> Void
    let onCreateBlankModifier: () -> Void
    let onSelectModifier: (GeneratorPoolEntry) -> Void

    private var presentation: TrackSourceContainedModifierPickerPresentation {
        TrackSourceContainedModifierPickerPresentation.resolve(
            step: step,
            compatibleModifierCount: compatibleModifiers.count
        )
    }

    var body: some View {
        StudioPanel(title: step.title, eyebrow: step.eyebrow, accent: StudioTheme.violet) {
            VStack(alignment: .leading, spacing: 16) {
                switch step {
                case .root:
                    rootContent
                case .modifierPool:
                    modifierPoolContent
                }

                controlsRow
            }
        }
    }

    private var rootContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            pickerActionButton(
                title: "New Blank Modifier",
                detail: "Create a compatible modifier for this slot.",
                accent: StudioTheme.violet,
                action: onCreateBlankModifier
            )

            poolEntryButton(
                title: "Select Modifier From Pool",
                detail: "Browse compatible modifier generators in this editor.",
                accent: StudioTheme.border,
                action: onShowModifierPool
            )
        }
    }

    private var modifierPoolContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let emptyStateTitle = presentation.emptyStateTitle {
                Text(emptyStateTitle)
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)

                Text("Create a blank modifier to recover without leaving this modifier tab.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)

                TrackSourceActionButton(
                    title: "New Blank Modifier",
                    accent: StudioTheme.violet,
                    action: onCreateBlankModifier
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(compatibleModifiers) { generator in
                            poolEntryButton(
                                title: generator.name,
                                detail: generator.kind.label,
                                accent: StudioTheme.violet,
                                action: { onSelectModifier(generator) }
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

    private func pickerActionButton(
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
            .padding(StudioMetrics.Spacing.standard)
            .background(
                accent.opacity(StudioOpacity.selectedFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
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
            .padding(StudioMetrics.Spacing.comfortable)
            .background(
                Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.ghostStroke), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
