import SwiftUI

struct TrackSourceGeneratorSelectionSheet: View {
    let title: String
    let generators: [GeneratorPoolEntry]
    let onSelect: (GeneratorPoolEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        StudioModal(
            title: title,
            subtitle: "Choose a compatible generator for this slot.",
            minWidth: 520,
            minHeight: 360,
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if generators.isEmpty {
                    Text("No compatible generators are available.")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                } else {
                    ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(generators) { generator in
                                    Button {
                                        onSelect(generator)
                                        dismiss()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(generator.name)
                                                .studioText(.bodyBold)
                                                .foregroundStyle(StudioTheme.text)
                                            Text(generator.kind.label)
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
                                            .stroke(StudioTheme.border, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 320)
                }
            }
        }
    }
}
