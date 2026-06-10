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
                                StudioOptionButton(title: generator.name, detail: generator.kind.label) {
                                    onSelect(generator)
                                    dismiss()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
            }
        }
    }
}
