import SwiftUI

/// Compact pattern-template chooser for one or more transient kit targets.
/// Template cells carry miniature pattern renders; overwrite detail is deferred
/// to the confirmation step where it is actionable.
struct DrumKitTemplateChooserSheet: View {
    let groupName: String
    let targetSlotIndexes: [Int]
    var accent: Color = StudioTheme.transportAccent
    let templates: [PatternTemplate]
    let previewProvider: (PatternTemplate, Int) -> PatternTemplateApplicationPreview
    let onApply: (PatternTemplate, [Int]) -> Void
    let onCancel: () -> Void

    @State private var selectedTemplateID: UUID?
    @State private var isConfirmingOverwrite = false

    init(
        groupName: String,
        targetSlotIndexes: [Int],
        accent: Color = StudioTheme.transportAccent,
        templates: [PatternTemplate] = DrumAssetLibrary.shared.templates,
        previewProvider: @escaping (PatternTemplate, Int) -> PatternTemplateApplicationPreview,
        onApply: @escaping (PatternTemplate, [Int]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.groupName = groupName
        self.targetSlotIndexes = Set(targetSlotIndexes)
            .filter { (0..<TrackPatternBank.slotCount).contains($0) }
            .sorted()
        self.accent = accent
        self.templates = templates
        self.previewProvider = previewProvider
        self.onApply = onApply
        self.onCancel = onCancel
    }

    private var selectedTemplate: PatternTemplate? {
        selectedTemplateID.flatMap { id in templates.first(where: { $0.id == id }) }
    }

    private var selectedPreviews: [(slotIndex: Int, preview: PatternTemplateApplicationPreview)] {
        guard let selectedTemplate else { return [] }
        return targetSlotIndexes.map { slotIndex in
            (slotIndex, previewProvider(selectedTemplate, slotIndex))
        }
    }

    private var targetLabel: String {
        targetSlotIndexes.map { "P\($0 + 1)" }.joined(separator: " + ")
    }

    private var canApplySelection: Bool {
        selectedPreviews.contains { !$0.preview.filledPartNames.isEmpty }
    }

    var body: some View {
        StudioModal(
            title: "Apply Template",
            accent: accent,
            minWidth: 620,
            minHeight: 430,
            onClose: onCancel
        ) {
            if isConfirmingOverwrite, let template = selectedTemplate {
                confirmStep(template: template, previews: selectedPreviews)
            } else {
                chooserStep
            }
        }
    }

    private var chooserStep: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.Spacing.standard) {
            Text(targetLabel)
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(accent)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(templates) { template in
                        templateCell(template)
                    }
                }

                if templates.isEmpty {
                    Text("No templates")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(StudioMetrics.Spacing.standard)
                }
            }
            .scrollIndicators(.never)

            HStack {
                Spacer()

                TrackSourceActionButton(title: "Apply", accent: accent) {
                    requestApply()
                }
                .disabled(selectedTemplate == nil || !canApplySelection)
                .help(applyHelp)
            }
        }
    }

    private var applyHelp: String {
        guard selectedTemplate != nil else { return "Choose a template" }
        guard canApplySelection else { return "This template has no matching parts in \(groupName)" }
        return "Apply to \(targetLabel)"
    }

    private func templateCell(_ template: PatternTemplate) -> some View {
        let isSelected = selectedTemplateID == template.id

        return Button {
            selectedTemplateID = template.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(template.name)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)

                templatePatternPreview(template)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                StudioTheme.subtleFill,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(
                        isSelected ? accent : StudioTheme.border,
                        lineWidth: isSelected ? StudioMetrics.emphasisBorderWidth : StudioMetrics.borderWidth
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(templateHelp(template))
        .accessibilityLabel("Template \(template.name)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func templatePatternPreview(_ template: PatternTemplate) -> some View {
        let rows = template.patterns
            .keys
            .sorted()
            .prefix(3)
            .compactMap { tag -> CompactStepPatternRowsPreview.Row? in
                guard let pattern = template.patterns[tag] else { return nil }
                return CompactStepPatternRowsPreview.Row(
                    label: PatternTemplateApplicationPreview.tagLabel(tag),
                    steps: Array(pattern.prefix(PatternTemplate.stepCount))
                )
            }

        return CompactStepPatternRowsPreview(
            rows: rows,
            accent: accent,
            labelWidth: 38,
            cellSize: 6
        )
    }

    private func templateHelp(_ template: PatternTemplate) -> String {
        let previews = targetSlotIndexes.map { previewProvider(template, $0) }
        let fills = stableUnique(previews.flatMap(\.filledPartNames))
        guard !fills.isEmpty else { return "No matching parts in \(groupName)" }
        return "Fills \(fills.joined(separator: ", ")) in \(targetLabel)"
    }

    private func requestApply() {
        guard let template = selectedTemplate, canApplySelection else { return }
        if selectedPreviews.contains(where: { $0.preview.requiresOverwriteConfirmation }) {
            isConfirmingOverwrite = true
        } else {
            onApply(template, targetSlotIndexes)
        }
    }

    private func confirmStep(
        template: PatternTemplate,
        previews: [(slotIndex: Int, preview: PatternTemplateApplicationPreview)]
    ) -> some View {
        let overwritten = stableUnique(previews.flatMap { $0.preview.overwrittenPartNames })
        let filled = stableUnique(previews.flatMap { $0.preview.filledPartNames })
        let freshFills = filled.filter { !Set(overwritten).contains($0) }
        let generatorSkipped = stableUnique(previews.flatMap { $0.preview.generatorSkippedPartNames })
        let duplicateSkipped = stableUnique(previews.flatMap { $0.preview.duplicateTagSkippedPartNames })

        return VStack(alignment: .leading, spacing: StudioMetrics.Spacing.comfortable) {
            Text("Apply \(template.name) to \(targetLabel)?")
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)

            confirmList(title: "Overwritten", names: overwritten, accent: StudioTheme.warning)

            if !freshFills.isEmpty {
                confirmList(title: "Filled", names: freshFills, accent: accent)
            }

            if !generatorSkipped.isEmpty {
                confirmList(title: "Generator skipped", names: generatorSkipped, accent: StudioTheme.mutedText)
            }

            if !duplicateSkipped.isEmpty {
                confirmList(title: "Duplicate skipped", names: duplicateSkipped, accent: StudioTheme.mutedText)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Back") {
                    isConfirmingOverwrite = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Overwrite and Apply") {
                    onApply(template, targetSlotIndexes)
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.warning)
            }
        }
    }

    @ViewBuilder
    private func confirmList(title: String, names: [String], accent: Color) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(accent)

                Text(names.joined(separator: ", "))
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.text)
            }
        }
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
