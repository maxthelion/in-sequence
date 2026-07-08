import SwiftUI

/// "Apply Template…" chooser for the kit matrix: lists the global pattern
/// templates with a tag-intersection preview against this group ("Fills Kick,
/// Snare — no Clap entry"), applies into the currently selected group pattern
/// slot, and inserts a confirm step listing overwrites when any targeted
/// member's slot is non-empty. Generator-backed slots are listed as skipped.
struct DrumKitTemplateChooserSheet: View {
    let groupName: String
    let targetSlotIndex: Int
    var accent: Color = StudioTheme.transportAccent
    let templates: [PatternTemplate]
    let previewProvider: (PatternTemplate, Int) -> PatternTemplateApplicationPreview
    let onApply: (PatternTemplate, Int) -> Void
    let onCancel: () -> Void

    @State private var selectedTemplateID: UUID?
    @State private var isConfirmingOverwrite = false

    init(
        groupName: String,
        targetSlotIndex: Int,
        accent: Color = StudioTheme.transportAccent,
        templates: [PatternTemplate] = DrumAssetLibrary.shared.templates,
        previewProvider: @escaping (PatternTemplate, Int) -> PatternTemplateApplicationPreview,
        onApply: @escaping (PatternTemplate, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.groupName = groupName
        self.targetSlotIndex = targetSlotIndex
        self.accent = accent
        self.templates = templates
        self.previewProvider = previewProvider
        self.onApply = onApply
        self.onCancel = onCancel
    }

    private var selectedTemplate: PatternTemplate? {
        selectedTemplateID.flatMap { id in templates.first(where: { $0.id == id }) }
    }

    private var selectedPreview: PatternTemplateApplicationPreview? {
        selectedTemplate.map { previewProvider($0, targetSlotIndex) }
    }

    var body: some View {
        StudioModal(
            title: "Apply Template",
            accent: accent,
            minWidth: 560,
            minHeight: 460,
            onClose: onCancel
        ) {
            if isConfirmingOverwrite, let template = selectedTemplate, let preview = selectedPreview {
                confirmStep(template: template, preview: preview)
            } else {
                chooserStep
            }
        }
    }

    // MARK: - Chooser step

    private var chooserStep: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.Spacing.comfortable) {
            ScrollView {
                VStack(alignment: .leading, spacing: StudioMetrics.Spacing.snug) {
                    ForEach(templates) { template in
                        templateRow(template)
                    }

                    if templates.isEmpty {
                        Text("No pattern templates available.")
                            .studioText(.body)
                            .foregroundStyle(StudioTheme.mutedText)
                            .padding(StudioMetrics.Spacing.standard)
                    }
                }
            }
            .scrollIndicators(.never)

            if let preview = selectedPreview, !preview.generatorSkippedPartNames.isEmpty {
                Text("Skipped (generator slot): \(preview.generatorSkippedPartNames.joined(separator: ", "))")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            if let preview = selectedPreview, !preview.duplicateTagSkippedPartNames.isEmpty {
                Text("Skipped (duplicate tag): \(preview.duplicateTagSkippedPartNames.joined(separator: ", "))")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            HStack {
                Spacer()

                TrackSourceActionButton(title: "Apply", accent: accent) {
                    requestApply()
                }
                .disabled(selectedTemplate == nil || selectedPreview?.filledPartNames.isEmpty != false)
                .help(applyHelp)
            }
        }
    }

    private var applyHelp: String {
        guard let preview = selectedPreview else {
            return "Choose a template first"
        }
        guard !preview.filledPartNames.isEmpty else {
            return "This template fills no parts of \(groupName)"
        }
        return "Apply into pattern slot P\(targetSlotIndex + 1)"
    }

    private func templateRow(_ template: PatternTemplate) -> some View {
        let isSelected = selectedTemplateID == template.id
        let preview = previewProvider(template, targetSlotIndex)

        return Button {
            selectedTemplateID = template.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(template.name)
                        .studioText(.bodyBold)
                        .foregroundStyle(StudioTheme.text)

                    Spacer(minLength: 0)
                }

                templatePatternPreview(template)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioMetrics.Spacing.compact)
            // Colour identifies, it never floods (ux-canon rule 12): the
            // template row stays neutral; selection reads from the outline.
            .background(
                StudioTheme.subtleFill,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(
                        isSelected ? accent : StudioTheme.border,
                        lineWidth: isSelected ? 2 : StudioMetrics.borderWidth
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(preview.summary)
        .accessibilityLabel("Template \(template.name)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func templatePatternPreview(_ template: PatternTemplate) -> some View {
        let rows = template.patterns
            .keys
            .sorted()
            .prefix(3)
            .compactMap { tag -> (String, [Bool])? in
                guard let pattern = template.patterns[tag] else { return nil }
                return (PatternTemplateApplicationPreview.tagLabel(tag), Array(pattern.prefix(PatternTemplate.stepCount)))
            }

        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    Text(row.0)
                        .studioText(.microEmphasis)
                        .foregroundStyle(StudioTheme.text)
                        .frame(width: 54, alignment: .leading)
                        .lineLimit(1)

                    HStack(spacing: 2) {
                        ForEach(Array(row.1.enumerated()), id: \.offset) { _, isOn in
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(isOn ? accent : StudioTheme.inset)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .stroke(StudioTheme.border.opacity(0.75), lineWidth: 0.5)
                                )
                        }
                    }
                }
            }
        }
    }

    private func requestApply() {
        guard let template = selectedTemplate, let preview = selectedPreview else { return }
        if preview.requiresOverwriteConfirmation {
            isConfirmingOverwrite = true
        } else {
            onApply(template, targetSlotIndex)
        }
    }

    // MARK: - Confirm step

    private func confirmStep(
        template: PatternTemplate,
        preview: PatternTemplateApplicationPreview
    ) -> some View {
        VStack(alignment: .leading, spacing: StudioMetrics.Spacing.comfortable) {
            Text("Applying \(template.name) into P\(targetSlotIndex + 1) will overwrite existing patterns.")
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)

            confirmList(
                title: "Overwritten",
                names: preview.overwrittenPartNames,
                accent: StudioTheme.warning
            )

            let freshFills = preview.filledPartNames.filter { !preview.overwrittenPartNames.contains($0) }
            if !freshFills.isEmpty {
                confirmList(title: "Filled (empty slot)", names: freshFills, accent: accent)
            }

            if !preview.generatorSkippedPartNames.isEmpty {
                confirmList(
                    title: "Skipped (generator slot)",
                    names: preview.generatorSkippedPartNames,
                    accent: StudioTheme.mutedText
                )
            }

            if !preview.duplicateTagSkippedPartNames.isEmpty {
                confirmList(
                    title: "Skipped (duplicate tag)",
                    names: preview.duplicateTagSkippedPartNames,
                    accent: StudioTheme.mutedText
                )
            }

            Spacer(minLength: 0)

            HStack {
                Button("Back") {
                    isConfirmingOverwrite = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Overwrite and Apply") {
                    onApply(template, targetSlotIndex)
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.warning)
            }
        }
    }

    private func confirmList(title: String, names: [String], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(accent)

            Text(names.joined(separator: ", "))
                .studioText(.body)
                .foregroundStyle(StudioTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
