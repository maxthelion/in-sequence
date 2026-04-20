import SwiftUI

struct GeneratedNotesPreview: View {
    let generatorParams: GeneratorParams
    let clipChoices: [ClipPoolEntry]

    var body: some View {
        let preview = previewSteps(for: generatorParams, clipChoices: clipChoices)
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(preview.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                            VStack(alignment: .leading, spacing: 4) {
                                if preview[index].isEmpty {
                                    Text("—")
                                        .foregroundStyle(StudioTheme.mutedText)
                                } else {
                                    ForEach(preview[index], id: \.self) { label in
                                        Text(label)
                                            .foregroundStyle(StudioTheme.text)
                                    }
                                }
                            }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .frame(width: 84, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            Text("Preview is generated from the current step and pitch settings.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
        }
    }
}
